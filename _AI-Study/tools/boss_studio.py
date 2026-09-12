#!/usr/bin/env python3
"""Local web UI for tweaking the boss generator and watching the teams change.

    tools/boss_studio.py            # http://127.0.0.1:8731
    tools/boss_studio.py --port N

Why a local server rather than a page you can share: generating a team needs the
game's PBS files, the Smogon set corpus and 86 MB of scraped teams, none of which a
sandboxed browser page can reach. It runs here or it does not run. Regenerating all
nine fights takes ~0.6 s, so every control re-generates as you move it.

READ-ONLY by default. `Export` writes a NEW file under generated/ and refuses to
overwrite one that exists unless you tick the box -- in particular it will not
silently replace teams_bosses_gyms.json, which is what is injected into the game.

The knobs are module globals in generate_bosses.py, read at call time, so `settings()`
swaps them in and puts them back. That is a deliberate choice over threading a config
object through 950 lines of a working generator: the studio is a previewer, and the
generator should not grow a parameter it only has because a UI exists. The two things
that are NOT plain globals get handled explicitly -- the level ladder is recomputed
through _remap_anchors(mode), and early_items() is cached but depends only on knobs
this UI does not expose.
"""
import collections
import contextlib
import datetime
import hashlib
import http.server
import json
import os
import random
import statistics
import sys
import threading
import urllib.parse

import boss_diagnostic as BD
import fight_context as FC
import free_team as FT
import generate_bosses as G
import generate_trainers as T
import smogon_corpus as SC
import team_shape as TS
import validate_team as V

PORT = 8731
GENDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "generated")
SHIPPED = os.path.join(GENDIR, "teams_bosses_gyms.json")
# Saved Builder configurations, shared between people through the repo the same way
# everything else here is. A preset is an INPUT, not an artifact, but it lives under
# generated/ so that one directory is the whole of what the studio writes.
PRESETS = os.path.join(GENDIR, "studio_presets")

# name -> (kind, min, max, step, help). Per-fight knobs are the nine-element lists.
SCALARS = {
    "CHASE": ("float", 0.5, 1.1, 0.05,
              "how universal a role must be before the archetype forces it; "
              "above 1.0 forces nothing"),
    "ON_THEME_MIN": ("int", 0, 6, 1, "how many of the six must match the type theme"),
    "TEAM_SIZE": ("int", 1, 6, 1, "mons per fight"),
    "MIN_CORR": ("float", 0, 100, 5,
                 "Smogon co-occurrence an off-theme pick must earn to take a slot"),
    "KEEP_DROP": ("int", 0, 5, 1,
                  "how many of the dev's own Pokemon a fight may spend on a floor "
                  "nothing else can cover; 0 keeps every one of them. A rival's core "
                  "families and whatever supplied the mode's evidence are never spent"),
    "KEEP_NEED_SET": ("int", 0, 1, 1,
                      "1 drops a dev Pokemon that has no published set surviving its "
                      "level -- its moves would be written from the learnset. Note it "
                      "cannot reach a mon PROTECTED as its fight's mode evidence, "
                      "which today is most of them: turn the modes off to see it work"),
    "KEEP_MIN_BAND": ("int", 0, 6, 1,
                      "0 is off; otherwise how many tier bands from the top a dev "
                      "Pokemon may sit in, over Uber/OU/UU/RU/NU/low. 3 means "
                      "\"Uber, OU or UU\" and drops 15 of the nine gyms' kept mons "
                      "-- a level-31 water gym is SUPPOSED to be low tier, so this "
                      "replaces rosters rather than repairing them"),
    "EARLY_MOVES": ("int", 0, 1, 1,
                    "1 lets a published set keep a move the species has not reached "
                    "yet instead of dropping it for filler. The species gate still "
                    "holds -- nothing gets a move it could never learn -- but these "
                    "builds DO fail validate_team.py's learnset check (16 errors on "
                    "the nine gyms), so only turn it on if the fangame is meant to "
                    "field precocious bosses"),
    "SET_SEED": ("int", 0, 40, 1,
                 "0 is off. Any other value rerolls WHICH published set each mon "
                 "gets, leaving the roster alone -- 9 to 20 of the 54 mons change "
                 "moves or item per seed, and the species almost never move. The "
                 "cheap reroll: drag it until a team reads right"),
    "PICK_SEED": ("int", 0, 40, 1,
                  "0 is off. Any other value rerolls WHICH SPECIES get picked, by "
                  "sampling inside the eBST band instead of taking the single "
                  "nearest body. Only the 35 GENERATED slots move; the dev's own "
                  "roster, the type theme and the band all still hold. Costs about "
                  "2 BST of mean deviation for a different team every notch"),
    "UBER_FROM": ("int", 0, 9, 1, "badge from which Ubers are legal"),
    "LEGEND_FROM": ("int", 0, 9, 1,
                    "badge from which a GENERATED pick may be a legendary or a "
                    "pseudo-legend; a leader's own one is always kept"),
    "LEGEND_BST": ("int", 500, 720, 10,
                   "BST at which a species counts as one. 580 is where the dex cuts "
                   "(580-599 is eighteen legendaries and nothing else); 600 spares "
                   "the 580 club, 570 would take the Ultra Beasts with it"),
    "UNLOCK_STAGE": ("int", 0, 9, 1, "badge from which megas and strong items unlock"),
    "BP_CAP": ("int", 40, 150, 5, "early-game move-power ceiling"),
    "BP_CAP_UNTIL": ("int", 0, 9, 1, "badge at which that ceiling lifts"),
}
# The globals answer two questions a person asks separately -- "how far into the game
# is this fight allowed to reach" and "what is on the roster" -- so they are two
# fieldsets rather than one column of fifteen sliders. The grouping lives here, next
# to the knobs it groups, and the assert below means a knob added to SCALARS without
# a home fails at import instead of quietly vanishing from the sidebar.
# level_mode and SET_FORMATS are listed with the sliders because they answer the same
# two questions (which ladder; which sets a build may draw from) even though neither
# is a range; the client renders those two itself and every other key as a slider.
GROUPS = [
    ("progression gates", ["level_mode", "UNLOCK_STAGE", "UBER_FROM", "LEGEND_FROM",
                           "LEGEND_BST", "BP_CAP", "BP_CAP_UNTIL", "EARLY_MOVES",
                           "per_fight"]),
    ("team", ["TEAM_SIZE", "ON_THEME_MIN", "CHASE", "MIN_CORR", "SET_FORMATS",
              "KEEP_DROP", "KEEP_NEED_SET", "KEEP_MIN_BAND"]),
    # A third question, and the reason these are not filed under "team": every other
    # knob here says what a team must BE, and these two only say "give me a different
    # one". Both are off at 0, and off is the shipped generator byte-for-byte.
    ("reroll", ["SET_SEED", "PICK_SEED"]),
]
assert {k for _, ks in GROUPS for k in ks} == set(SCALARS) | {
    "level_mode", "SET_FORMATS", "per_fight"}
# Per-fight knobs the UI sends as nine-element lists, badge order. THEME is the odd
# one out: in the generator it is a DICT keyed by leader name, not a list, so it needs
# converting in both directions. Treating it as a list handed the UI nine leader names
# as its "types" and replaced the dict with a list, which make_gym then indexed with a
# string -- TypeError on the first control anyone touched.
# SET_FORMATS rides with the lists rather than the scalars: it is a set of
# strings, not a slider, and settings() already restores whatever it swaps.
# An empty tick list is falsy and therefore never applied, which is right --
# "none ticked" and "all formats" are the same instruction.
LISTS = ["TARGET", "SPREAD", "ARCHETYPE", "MODE", "SET_FORMATS"]
# A <select> cannot send None, so the "no mode" option sends "". Everything
# downstream treats "" exactly as None (plan_for, affinity and dedupe_roles all test
# the mode for truthiness), but the generator's own default is None and a round trip
# through the UI should not quietly change its type.
NO_MODE = ""


def _fight_picks(raw):
    """Card keys -> fight ids. "g3" is gym 4, "t7" the eighth fight load_fights()
    yields. The client is given indices and never a name, because the trainer cards
    are anonymised and a fight id spells the trainer out."""
    fights = T.load_fights()
    out = {}
    for k, v in (raw or {}).items():
        if k[:1] == "g" and k[1:].isdigit() and int(k[1:]) < len(G.CAPS):
            key = G.gym_id(int(k[1:]))
        elif k[:1] == "t" and k[1:].isdigit() and int(k[1:]) < len(fights):
            key = T.fight_id(fights[int(k[1:])])
        else:
            continue
        sets = {sp: ([lbl] if isinstance(lbl, str) else list(lbl))
                for sp, lbl in (v.get("sets") or {}).items() if lbl}
        out[key] = {"keep": v.get("keep") or {}, "sets": sets}
    return out


def _leaders():
    return [c["trainer"] for c in G.CAPS]


def theme_list():
    return [G.THEME[n] for n in _leaders()]


# settings() mutates module globals, and the server is threaded: an overlapping
# request -- a browser tab regenerating on a slider while something else calls the
# API -- reads another request's knobs mid-build and returns a team from a state
# neither caller asked for. It shows up as irreproducible numbers rather than an
# error. Generation is ~0.6 s and single-user, so serialising it costs nothing.
_LOCK = threading.Lock()


@contextlib.contextmanager
def settings(over):
    """Apply overrides to the generator's globals, then put everything back.

    Caller must hold _LOCK: these are process-wide globals, not per-request state."""
    saved = {k: getattr(G, k) for k in list(SCALARS) + LISTS + ["THEME", "PICKS"]
             if hasattr(G, k)}
    saved["_TS_CHASE"], saved["_AX"], saved["_AY"] = TS.CHASE, G._AX, G._AY
    try:
        for k in LISTS:
            if over.get(k):
                setattr(G, k, [v or None for v in over[k]] if k == "MODE"
                        else list(over[k]))
        if over.get("THEME"):
            G.THEME = dict(zip(_leaders(), over["THEME"]))
        G.PICKS = _fight_picks(over.get("PICKS"))
        for k in SCALARS:
            if over.get(k) is None:
                continue
            if k == "CHASE":
                TS.CHASE = float(over[k])
            else:
                setattr(G, k, type(saved[k])(over[k]))
        if over.get("level_mode"):
            _, G._AX, G._AY = G._remap_anchors(over["level_mode"])
        yield
    finally:
        TS.CHASE, G._AX, G._AY = saved.pop("_TS_CHASE"), saved.pop("_AX"), saved.pop("_AY")
        for k, v in saved.items():
            setattr(G, k, v)


def _null(n, draws=3000):
    """Distribution of role-vector spread for `n` real teams. Independent of every
    knob, so it is computed once and reused for the rest of the session."""
    rows = TS.profile()["sample"]["rows"]
    nr = len(TS.ROLES)
    rng = random.Random(11)
    return [BD.spread([rng.choice(rows)[:nr] for _ in range(n)]) for _ in range(draws)]


_NULL = {}


# A Builder card never names the fight. A rival keeps ONE number across every
# encounter, which is the useful half of the identity and the half that is not a
# spoiler; the trainer CLASS is dropped with the name, since OWEN1 gives it away just
# as plainly. Numbered off generate_trainers' own tuples rather than off encounter
# order, so a label means the same thing between runs. JEREBUZO is Jeremiah's second
# class -- the same person, same four species with Piloswine evolved -- so it folds
# onto his letter instead of claiming a new one.
_SAME_PERSON = {"JEREBUZO": "JEREMIAH"}
_NAMED = [t for t in T.BOSSES if t not in _SAME_PERSON]


def _alias(trainer_type):
    who = _SAME_PERSON.get(trainer_type, trainer_type)
    if who in T.RIVALS:
        return f"Rival {T.RIVALS.index(who) + 1}"
    if who in _NAMED:
        return f"Named trainer {chr(65 + _NAMED.index(who))}"
    return "Named trainer"


def _ordinal(n):
    return f"{n}{'th' if 10 <= n % 100 <= 20 else {1:'st',2:'nd',3:'rd'}.get(n % 10, 'th')}"


def _card(build, **extra):
    """One team's Builder card.

    Shared by the nine gyms and the named trainers: "what plan, what curve, what
    floors, which mons, and does the roster cover anything" is the same question
    about both, and this was an inline block a trainers section would have copied.
    `level` goes through T.show_level because a scaled fight's level is a
    ["balanceo", offset] cell, not an int."""
    team = build["team"]
    # The generator's own tally, not a re-read of the move names. Roles can come from
    # an ABILITY (Sand Stream is the sand setter; Swift Swim is a rain abuser) and
    # `<mode>_abuse` is not in ROLE_MOVES at all, so role_counts scored gym 6's sand
    # 1/3 where the build meets 3/3. The variety vector below still uses role_counts,
    # and must: it is compared against corpus teams, for which only moves are known.
    rc = dict(build["roles"])
    floors = {r: v for r, v in build["floors"].items() if r != "mega"}
    arch = build["archetype"]
    # A rival's roster can hold an engine-resolved starter slot (`owenpoke2`), which
    # has no species row, no EVs and no moves -- it becomes whatever counters the
    # player's starter at battle time. It is shown, and it is excluded from every
    # measurement, because there is nothing here to measure.
    real = [m for m in team if not G.is_dynamic(m["species"])]
    return dict({
        "archetype": arch,
        # The other half of the plan. Without it the Builder shows teams built around
        # a mode and never says which, and the mode is the half that decides what the
        # fight is about.
        "mode": build["mode"],
        "target": build["target"], "level": build["level"],
        "ebst": round(sum(G.ebst(m) for m in real) / max(len(real), 1)),
        "offence": round(TS.team_offence(
            [dict(zip(BD.PBS_EV, m["ev"])) for m in real])) if real else 0,
        "ev_target": (round(TS.profile()["archetype"][arch]["offence"])
                      if arch else None),
        "floors": floors,
        "met": sum(1 for r, v in floors.items() if rc.get(r, 0) >= v),
        "roles": {k: v for k, v in rc.items() if v},
        "mega": next((m["species"] for m in real
                      if m["item"] in G.MEGASTONE), None),
        "notes": build["notes"],
        # The type-coverage read the free cards carry. A Builder card said how well a
        # team met its FLOORS and nothing about whether the six of them cover
        # anything -- the axis these teams actually failed on.
        "judge": {k: v["value"] for k, v in FT.judge(FT._team_mons(
            [m["species"] for m in real],
            {m["species"]: m["moves"] for m in real}))["axes"].items()},
        "mons": [{"species": m["species"], "level": T.show_level(m["level"]),
                  "item": m.get("item"), "nature": m.get("nature"),
                  "ev": m.get("ev"), "moves": m.get("moves") or [],
                  "kept": m.get("kept"), "why": m.get("why"),
                  "fidelity": m.get("fidelity"), "src": m.get("src"),
                  "dynamic": G.is_dynamic(m["species"]),
                  "pinned": bool(m.get("pinned")),
                  "ability": None if G.is_dynamic(m["species"])
                             else G.ability_name(m)} for m in team],
    }, **extra)


def run(over):
    with _LOCK, settings(over):
        gyms = [G.make_gym(i) for i in range(9)]
        type_ids = G._type_ids()
        records = [G.as_team_record(g, type_ids) for g in gyms]
        out = [_card(g, idx=g["idx"], theme=g["theme"]) for g in gyms]
        # The named non-gym trainers -- rivals, the recurring bosses, the post-game
        # superboss. A different generator owns them and a DIFFERENT file ships them,
        # so they are reported beside the gyms and deliberately kept out of
        # `records`, which is what /api/export writes to teams_bosses_gyms.json.
        # Sparse on purpose: an entry means "you chose this on the card", and its
        # absence means "use the plan on file". A full list would silently freeze all
        # 18 fights at whatever they happened to derive to the first time the page
        # loaded. `slot` is the index into load_fights() -- a stable handle that is
        # not a name, since the cards no longer carry one.
        tplans = {int(k): v for k, v in (over.get("TRAINER_PLANS") or {}).items()}
        trainers = []
        for i, b in enumerate(T.load_fights()):
            pick = tplans.get(i)
            got = T.make_trainer(b, (pick[0] or None, pick[1] or None) if pick else None)
            if got:
                trainers.append(_card(got, slot=i, who=_alias(b["type"]),
                                      ace=got["ace"], dynamic=got["dynamic"]))
        trainers.sort(key=lambda c: (c["target"], c["who"]))
        # Second encounters only once the order is fixed, so "Rival 1 (2nd)" is the
        # second one up the curve rather than the second one out of load_fights().
        nth = collections.Counter()
        for c in trainers:
            nth[c["who"]] += 1
            if nth[c["who"]] > 1:
                c["who"] += f" ({_ordinal(nth[c['who']])})"
        # `slot` stays -- it is how a card sends its override back -- but nothing
        # that spells the trainer out does.
        errs, warns = V.validate(records)
        vec = [[TS.role_counts(g["team"], lambda m: m["moves"])[k] for k in TS.ROLES]
               for g in gyms]
        null = _NULL.setdefault(len(vec), _null(len(vec)))
        got = BD.spread(vec)
        return {
            "gyms": out, "trainers": trainers, "records": records,
            # A fingerprint of the TEAMS, not of the settings that asked for them.
            # Those are different claims: identical settings reproduce identical
            # teams only while the PBS tables, the Smogon dump and this generator all
            # hold still, and a preset that silently builds something else on another
            # machine is the exact failure a shared preset is supposed to prevent. So
            # a preset records what it produced, and loading one says whether you got
            # it. Trainers are in here as well as the gyms: "the same team" means all
            # 27 fights, even though only the nine are what /api/export writes.
            "sha": _sha(records, trainers),
            "errors": errs, "warnings": warns,
            "mad": round(statistics.mean(
                [abs(o["ebst"] - o["target"]) for o in out]), 1),
            "variety": {
                "got": round(got, 2), "mean": round(statistics.mean(null), 2),
                "pctile": round(100 * sum(1 for s in null if s < got) / len(null), 1)},
        }


# One fight's candidate set is 4-5 archetypes x 1-4 modes, each a real build: ~1.5 s.
# That is fine to wait for once and not fine to recompute every time the panel is
# reopened, so it is cached against the knobs it was built under -- change a knob and
# the key changes with it.
_CANDIDATES = {}


def candidates(fight_id, how, over):
    key = (fight_id, how, json.dumps(over, sort_keys=True, default=str))
    if key in _CANDIDATES:
        return _CANDIDATES[key]
    with _LOCK, settings(over):
        match = [f for f in FC.fights() if f["id"] == fight_id]
        if not match:
            raise KeyError(fight_id)
        ctx = FC.derive(match[0])
        got = FC.candidates(ctx, how)
        out = {
            "fight": fight_id, "label": ctx["label"], "kind": ctx["kind"],
            "theme": ctx["theme"], "warn": ctx["warn"], "stage": ctx["stage"],
            "target": ctx["target"], "core": ctx["core"],
            "spine": [n for n, _w in ctx["spine"]],
            "rejected": ctx["plans"]["rejected"],
            "evidence": ctx["plans"]["evidence"],
            "plans": [{
                "archetype": s["archetype"], "mode": s["mode"],
                "evidence": s["evidence"], "met": s["met"], "need": s["need"],
                "missed": s["missed"], "gap": s["gap"],
                # A gated plan is one whose MODE the fight cannot claim -- no real
                # setter or abuser on the roster, or no ability setter in its band.
                # It still builds, and it is still shown, but without this the card
                # is indistinguishable from a plan the deriver would pick.
                "gated": s["gated"],
                "gate_why": ctx["plans"]["rejected"].get(s["mode"], ""),
                "incumbent": s["incumbent"],
                # The type-coverage read the free cards already carry. A plan card
                # said how well a team met its FLOORS and nothing about whether the
                # six of them cover anything -- which is the axis the nine gyms
                # actually failed on (4/9 distinct type combinations).
                "judge": {k: v["value"] for k, v in FT.judge(FT._team_mons(
                    [m["species"] for m in s["team"]],
                    {m["species"]: m["moves"] for m in s["team"]}))["axes"].items()},
                "mons": [{"species": m["species"], "level": m["level"],
                          "item": m["item"], "moves": m["moves"], "kept": m["kept"],
                          "why": m["why"], "fidelity": m["fidelity"],
                          "src": m["src"], "ability": G.ability_name(m)}
                         for m in s["team"]],
            } for s in got],
        }
    _CANDIDATES[key] = out
    return out


MAX_VARIATIONS = 40
_FREE = {}


def free_build(payload):
    """One free-build request: N variations around the caller's cores.

    Runs under the same lock and the same knob swap as candidates(), because it goes
    through the same generator globals -- BP_CAP, UBER_FROM and the rest still apply,
    and a concurrent Builder regenerate would otherwise read them mid-swap."""
    key = json.dumps(payload, sort_keys=True)
    if key in _FREE:
        return _FREE[key]

    cores = [c for c in (payload.get("cores") or []) if c]
    unknown = [c for c in cores if FT.fold(c) is None]
    if unknown:
        return {"error": "not in this game's dex: " + ", ".join(unknown)}

    target = int(payload.get("target") or 520)
    spread = int(payload.get("spread") or 160)
    filters = {
        "cores": [FT.fold(c) for c in cores],
        "level": max(1, int(payload.get("level") or 50)),
        "stage": 8, "size": max(1, min(6, int(payload.get("size") or 6))),
        "target": target, "lo": target - spread / 2, "hi": target + spread / 2,
        "archetype": payload.get("archetype") or "balance",
        "mode": payload.get("mode") or None,
        "tier_ceiling": payload.get("tier_ceiling") or None,
        "gens": set(payload.get("gens") or ()),
        "drop_floors": payload.get("drop_floors") or [],
        "per_set": max(1, int(payload.get("per_set") or 3)),
        # {SPECIES: [labels]} -> {SPECIES: set(labels)}. An empty list means "any",
        # which is what an untouched picker sends, so it must not become a filter
        # that matches nothing.
        "set_filter": {k: set(v) for k, v in
                       (payload.get("set_filter") or {}).items() if v},
        "allow_mega": bool(payload.get("allow_mega", True)),
        "types": set(payload.get("types") or ()),
        "explain": bool(payload.get("explain")),
        "set_formats": payload.get("set_formats") or (),
        "early_moves": bool(payload.get("early_moves")),
    }
    # 24 distinct variations cost 1.4 s, so the old ceiling of 12 was bounding
    # nothing worth bounding -- it just silently rewrote a request for 33 into 12
    # and then reported "12 distinct" as though the filters had run out. A clamp the
    # caller cannot see is worse than a slow request; this one is reported.
    asked = max(1, int(payload.get("count") or 5))
    count = min(MAX_VARIATIONS, asked)
    with _LOCK, settings(payload.get("settings") or {}):
        got = FT.build(filters, count)
        out = {"distinct": got["distinct"], "asked": got["asked"],
               "requested": asked, "cap": MAX_VARIATIONS,
               "core_sets": got["core_sets"], "per_set": got["per_set"],
               "groups": [{"core": [{"species": m["species"], "item": m["item"],
                                     "ability": G.ability_name(m),
                                     "moves": m["moves"], "src": m["src"],
                                     "fidelity": m["fidelity"]}
                                    for m in g["teams"][0]["team"]
                                    if m["species"] in set(got["cores"])],
                           "seeds": [v["seed"] for v in g["teams"]]}
                          for g in got["groups"]],
               "tried": got["tried"], "basis": got["basis"],
               "cores": filters["cores"], "variations": []}
        for v in got["variations"]:
            mons = FT._team_mons([m["species"] for m in v["team"]],
                                 {m["species"]: m["moves"] for m in v["team"]})
            axes = FT.judge(mons)["axes"]
            out["variations"].append({
                "seed": v["seed"], "notes": v["notes"], "plan": v["plan"],
                "trace": v.get("trace"),
                "judge": {k: axes[k]["value"] for k in axes},
                "paste": FT.showdown_paste(v["team"]),
                # The evidence behind the pick, not just the pick. `support` is
                # the number rank_for actually ranked on, so a card can say why a
                # mon is there; a core has none by construction -- it is the query,
                # not an answer to it.
                "mons": [{"species": m["species"], "level": m["level"],
                          "item": m["item"], "moves": m["moves"],
                          "kept": m["kept"], "why": m["why"],
                          "fidelity": m["fidelity"], "src": m["src"],
                          "ability": G.ability_name(m),
                          "support": (None if m["kept"] or not got["basis"] else
                                      round(100 * got["support"].get(m["species"], 0)
                                            / got["basis"], 1)),
                          "marginal": (None if m["kept"] else
                                       round(got["marginal"].get(m["species"], 0), 1))}
                         for m in v["team"]],
            })
    _FREE[key] = out
    return out


def defaults():
    with open(SHIPPED, encoding="utf-8") as fh:
        shipped = json.load(fh)
    curve = json.load(open(os.path.join(GENDIR, "realidea_level_curve.json")))
    return {
        "scalars": {k: (TS.CHASE if k == "CHASE" else getattr(G, k))
                    for k in SCALARS},
        "meta": {k: list(v) for k, v in SCALARS.items()},
        "groups": GROUPS,
        "lists": dict({k: [v if v is not None else NO_MODE
                            for v in getattr(G, k)] for k in LISTS},
                      THEME=theme_list()),
        "types": sorted(G.WEAK),
        "archetypes": TS.ARCHETYPES,
        "modes": [NO_MODE] + list(TS.MODE_ROLES),
        "any": FT.ANY,
        "fights": [{"id": f["id"], "label": f["label"], "kind": f["kind"]}
                   for f in FC.fights()],
        "plans": G.load_plans(),
        "level_mode": curve["active_mode"],
        "level_modes": ["expert", "vanilla"],
        "dex": FT.dex(),
        "generations": FT.GENERATIONS,
        "tiers": SC.RANK,
        # Every role any archetype can make mandatory, so the UI can offer to turn
        # each one off. `mega` is in here for the same reason the others are.
        "set_tiers": SC.set_tiers(),
        "floor_roles": sorted({r for a in TS.ARCHETYPES
                               for r in G.plan_for(a, True, None)[0]}),
        "shipped": {t["id"]: [m["species"] for m in t["mons"]] for t in shipped},
    }


def _sha(records, trainers):
    blob = json.dumps([records, [(t["slot"], t["mons"]) for t in trainers]],
                      sort_keys=True, default=str)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:12]


def _preset_path(name):
    """generated/studio_presets/<name>.json, and never anywhere else.

    basename() first: the name arrives from a text field, and "../../PBS/pokemon.txt"
    is a path this would otherwise happily write to."""
    name = os.path.basename((name or "").strip()) or "preset"
    if not name.endswith(".json"):
        name += ".json"
    return os.path.join(PRESETS, name)


def preset_list():
    try:
        names = sorted(n for n in os.listdir(PRESETS) if n.endswith(".json"))
    except FileNotFoundError:
        return []
    out = []
    for n in names:
        try:
            with open(os.path.join(PRESETS, n), encoding="utf-8") as fh:
                got = json.load(fh)
            out.append({"name": n[:-5], "saved": got.get("saved"),
                        "sha": got.get("sha"), "note": got.get("note") or ""})
        except (ValueError, OSError):
            continue                       # a corrupt preset hides itself, not the list
    return out


def preset_save(name, over, note=""):
    """Build under `over`, then write the settings and what they produced."""
    got = run(over)
    os.makedirs(PRESETS, exist_ok=True)
    dest = _preset_path(name)
    body = {"name": os.path.basename(dest)[:-5],
            "saved": datetime.datetime.now().replace(microsecond=0).isoformat(),
            "note": note, "sha": got["sha"], "settings": over}
    with open(dest, "w", encoding="utf-8") as fh:
        json.dump(body, fh, indent=1, sort_keys=True)
        fh.write("\n")
    return {"ok": os.path.relpath(dest), "sha": got["sha"],
            "errors": len(got["errors"])}


def preset_load(name):
    with open(_preset_path(name), encoding="utf-8") as fh:
        got = json.load(fh)
    return {"name": got.get("name"), "saved": got.get("saved"),
            "note": got.get("note") or "", "sha": got.get("sha"),
            "settings": got.get("settings") or {}}


class Handler(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        raw = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def log_message(self, *a):
        pass

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/":
            return self._send(200, PAGE, "text/html; charset=utf-8")
        if path == "/api/state":
            return self._send(200, json.dumps(defaults()))
        if path == "/api/presets":
            return self._send(200, json.dumps({"presets": preset_list()}))
        if path == "/api/preset":
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            try:
                return self._send(200, json.dumps(preset_load(q.get("name", [""])[0])))
            except (OSError, ValueError) as exc:
                return self._send(404, json.dumps({"error": f"cannot read it: {exc}"}))
        if path == "/api/candidates":
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            try:
                return self._send(200, json.dumps(candidates(
                    q.get("fight", [""])[0], q.get("sort", ["evidence"])[0],
                    json.loads(q.get("settings", ["{}"])[0]))))
            except KeyError as exc:
                return self._send(404, json.dumps({"error": f"no fight {exc}"}))
            except Exception as exc:                   # noqa: BLE001 - show it in the UI
                return self._send(500, json.dumps(
                    {"error": f"{type(exc).__name__}: {exc}"}))
        self._send(404, '{"error":"not found"}')

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        n = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(n) or b"{}")
        except ValueError:
            return self._send(400, '{"error":"bad json"}')
        try:
            if path == "/api/generate":
                r = run(body)
                r.pop("records")
                return self._send(200, json.dumps(r))
            if path == "/api/sets":
                sp = FT.fold(body.get("species") or "")
                if not sp:
                    return self._send(200, json.dumps({"sets": [], "species": None}))
                return self._send(200, json.dumps(
                    {"species": sp,
                     "sets": FT.sets_for(sp, max(1, int(body.get("level") or 50)),
                                         bool(body.get("allow_mega", True)))}))
            if path == "/api/free":
                return self._send(200, json.dumps(free_build(body)))
            if path == "/api/plan":
                saved = FC.record(body["fight"], body.get("archetype") or None,
                                  body.get("mode") or None,
                                  {k: body[k] for k in ("evidence", "gap",
                                                        "floors_met") if k in body})
                return self._send(200, json.dumps(
                    {"ok": os.path.relpath(G.PLANS_PATH), "entry": saved}))
            if path == "/api/preset":
                if not (body.get("name") or "").strip():
                    return self._send(400, json.dumps({"error": "name it first"}))
                dest = _preset_path(body["name"])
                if os.path.exists(dest) and not body.get("overwrite"):
                    return self._send(409, json.dumps(
                        {"error": f"{os.path.basename(dest)} exists — tick overwrite"}))
                return self._send(200, json.dumps(preset_save(
                    body["name"], body.get("settings") or {}, body.get("note") or "")))
            if path == "/api/export":
                name = os.path.basename(body.get("name") or "teams_bosses_studio.json")
                if not name.endswith(".json"):
                    name += ".json"
                dest = os.path.join(GENDIR, name)
                if os.path.exists(dest) and not body.get("overwrite"):
                    return self._send(409, json.dumps(
                        {"error": f"{name} exists — tick overwrite to replace it"}))
                r = run(body.get("settings") or {})
                with open(dest, "w", encoding="utf-8") as fh:
                    json.dump(r["records"], fh, indent=1)
                    fh.write("\n")
                return self._send(200, json.dumps(
                    {"ok": os.path.relpath(dest), "errors": len(r["errors"])}))
        except Exception as exc:                       # noqa: BLE001 - show it in the UI
            return self._send(500, json.dumps({"error": f"{type(exc).__name__}: {exc}"}))
        self._send(404, '{"error":"not found"}')


PAGE = r"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Boss Studio</title>
<style>
*{box-sizing:border-box}body{margin:0}[hidden]{display:none!important}
:root{--bg:#fbfaf8;--fg:#1b1a18;--dim:#6b6762;--line:#e2ddd6;--card:#fff;--ok:#1f7a4d;
      --warn:#9a6a00;--bad:#b23c2e;--accent:#3b5bdb}
:root:not([data-theme=light]){@media (prefers-color-scheme:dark){
  --bg:#16150f;--fg:#ece8e1;--dim:#9a948c;--line:#2f2d27;--card:#1e1d17;
  --ok:#6bbf8f;--warn:#d6a640;--bad:#e2705f;--accent:#8aa2ff}}
:root[data-theme=dark]{--bg:#16150f;--fg:#ece8e1;--dim:#9a948c;--line:#2f2d27;
  --card:#1e1d17;--ok:#6bbf8f;--warn:#d6a640;--bad:#e2705f;--accent:#8aa2ff}
body{background:var(--bg);color:var(--fg);font:13px/1.45 ui-sans-serif,system-ui,sans-serif}
.wrap{display:grid;grid-template-columns:320px 1fr;gap:18px;padding:0 16px 16px;
      max-width:1600px}
@media(max-width:900px){.wrap{grid-template-columns:1fr}}
h1{font-size:15px;margin:0;letter-spacing:.02em}
.sub{color:var(--dim);font-size:12px;margin-bottom:14px}
.bar{display:flex;align-items:baseline;gap:16px;padding:14px 16px 12px;max-width:1600px;
     border-bottom:1px solid var(--line);margin-bottom:16px}
.bar nav{display:flex;gap:4px}
.tab{background:transparent;color:var(--dim);border:1px solid transparent;
     border-radius:6px;padding:4px 12px;font:inherit;font-weight:600;font-size:12px;
     cursor:pointer}
.tab.on{background:var(--card);color:var(--fg);border-color:var(--line)}
.panel{position:sticky;top:16px;align-self:start;max-height:calc(100vh - 32px);overflow:auto}
fieldset{border:1px solid var(--line);border-radius:8px;padding:10px 12px;margin:0 0 12px;
         background:var(--card)}
fieldset fieldset{margin-bottom:0}
legend{font-size:11px;text-transform:uppercase;letter-spacing:.08em;color:var(--dim);padding:0 4px}
.row{display:grid;grid-template-columns:1fr auto;gap:6px;align-items:center;margin:7px 0}
.row label{font-size:12px}
.row .v{font-variant-numeric:tabular-nums;color:var(--accent);font-weight:600;min-width:42px;
        text-align:right}
input[type=range]{grid-column:1/-1;width:100%;accent-color:var(--accent)}
.grp{margin-bottom:10px;border-left:2px solid #3d6ea5;background:#141a22;
  border-radius:0 3px 3px 0}
.grp>summary{cursor:pointer;padding:6px 10px;display:flex;align-items:center;
  gap:8px;flex-wrap:wrap;list-style:none}
.grp>summary::-webkit-details-marker{display:none}
.grp>summary::before{content:'\25b8';color:#8b95a3;font-size:10px}
.grp[open]>summary::before{content:'\25be'}
.grp>.cand{margin:0 10px 10px}
.grphead{font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:#8b95a3}
.coreline{font-size:11px;color:#c7d0dc}
.prov{font-size:10px;color:#6c7684;flex-basis:100%;padding-left:14px}
.picks{margin-top:6px;border:1px solid #243041;border-radius:3px}
.picks>summary{cursor:pointer;padding:5px 8px;font-size:11px;color:#8b95a3}
.picks table{width:100%;border-collapse:collapse;font-size:10px;
  font-variant-numeric:tabular-nums}
.picks th{text-align:right;color:#6c7684;font-weight:500;padding:2px 5px}
.picks th:nth-child(2){text-align:left}
.picks td{text-align:right;padding:1px 5px;color:#9aa5b3;white-space:nowrap}
.picks td:nth-child(2){text-align:left;color:#c7d0dc}
.picks tr.took td{color:#e8c15f;font-weight:600}
.picks .band{color:#5d6775}
.pickshead{padding:5px 8px;font-size:11px;color:#8b95a3;border-top:1px solid #1b2431}
.pickshead b{color:#c7d0dc;font-weight:600}
.setpick{margin-top:6px;border:1px solid #243041;border-radius:3px}
.setpick>summary{cursor:pointer;padding:5px 8px;display:flex;gap:6px;
  align-items:center;flex-wrap:wrap}
.setrow{display:grid;grid-template-columns:auto 1fr;gap:2px 6px;padding:4px 8px;
  border-top:1px solid #1b2431;font-size:11px;align-items:start}
.setrow .setname{color:#c7d0dc}
.setrow .sub,.setrow .tag{grid-column:2}
.why{font-size:10px;color:#7d8694;margin-top:2px;line-height:1.4}
pre.paste{white-space:pre-wrap;font-size:11px;line-height:1.5;
  background:#0d1117;border:1px solid #243041;border-radius:4px;padding:8px;
  margin:6px 0 0;overflow-x:auto}
.gens{display:flex;flex-wrap:wrap;gap:2px 10px;font-size:11px}
.gens label{display:flex;align-items:center;gap:3px;white-space:nowrap}
select,input[type=text]{background:var(--bg);color:var(--fg);border:1px solid var(--line);
        border-radius:5px;padding:3px 5px;font:inherit;font-size:12px;width:100%}
table{border-collapse:collapse;width:100%;font-size:12px}
th,td{text-align:left;padding:3px 5px;border-bottom:1px solid var(--line);vertical-align:middle}
th{font-size:10px;text-transform:uppercase;letter-spacing:.06em;color:var(--dim);font-weight:600}
td.n{text-align:right;font-variant-numeric:tabular-nums}
.stats{display:flex;gap:16px;flex-wrap:wrap;border:1px solid var(--line);border-radius:8px;
       padding:10px 14px;background:var(--card);margin-bottom:14px;align-items:baseline}
.stat b{font-size:17px;font-variant-numeric:tabular-nums}
.stat span{color:var(--dim);font-size:11px;text-transform:uppercase;letter-spacing:.06em;
           display:block}
.tag.van{background:var(--accent);color:var(--card);opacity:.85}
/* A card carrying overrides. Distinct from the rest at a glance, because the whole
   point of the per-card controls is that most cards are NOT carrying any. */
.gym.dirty{border-color:var(--accent);
  box-shadow:0 0 0 1px color-mix(in srgb,var(--accent) 45%,transparent)}
.tag.edited{background:var(--accent);color:var(--card);font-weight:600}
button.tiny[disabled]{opacity:.35;cursor:default}
/* An overridden row is marked on its edge as well as with a tag: the tag says WHAT
   and the stripe says WHERE, so a card with one pinned mon reads at a glance. */
.mon.ispin,.mon.isset{padding-left:9px;margin-left:-12px;padding-right:5px;
  margin-right:-5px;border-radius:0 3px 3px 0}
.mon.ispin{border-left:4px solid var(--accent);
  background:color-mix(in srgb,var(--accent) 12%,transparent)}
.mon.isset{border-left:4px dashed var(--accent);
  background:color-mix(in srgb,var(--accent) 6%,transparent)}
.mon.ispin.isset{border-left-style:solid}
/* The row is the affordance: no furniture until you click it. */
.mon.editable{cursor:pointer}
.mon.editable:hover{background:color-mix(in srgb,var(--accent) 7%,transparent)}
.mon.open{background:color-mix(in srgb,var(--accent) 10%,transparent)}
.edit{display:grid;gap:5px;margin:6px 0 2px;padding:7px;border-radius:3px;
  background:var(--bg);border:1px solid var(--line);cursor:default}
.edit label{display:grid;gap:2px;font-size:10px;color:var(--dim)}
.edit label.keep{display:flex;gap:5px;align-items:center}
.edit input[list],.edit select{font-size:11px;padding:2px 4px;min-width:0}
/* A build in flight: the cards below are a picture of the PREVIOUS answer, so they
   are dimmed and made inert rather than left looking current and clickable. */
.busy #gyms,.busy #trainers{opacity:.4;pointer-events:none}
.busy #stats::after{content:'building…';font-size:11px;color:var(--accent);
  align-self:center;margin-left:8px}
.pin{display:flex;gap:5px;align-items:center;margin:3px 0 1px}
.pin select{font-size:9px;flex:1;min-width:0}
.pin input{margin:0}
.plan{display:flex;gap:4px}
.plan select{font-size:10px;padding:1px 3px}
.sect{font-size:12px;text-transform:uppercase;letter-spacing:.08em;color:var(--dim);margin:18px 0 8px;font-weight:600}
.gyms{display:grid;grid-template-columns:repeat(auto-fill,minmax(330px,1fr));gap:12px}
.gym{border:1px solid var(--line);border-radius:8px;background:var(--card);padding:10px 12px}
/* a plan whose mode the fight cannot claim: shown so you can see what it would cost,
   dimmed so it cannot be mistaken for one the deriver would choose */
.cand.gated{opacity:.5}
.cand.gated:hover{opacity:1}
.tag.bad{border-color:var(--bad);color:var(--bad)}
.tag.accent{border-color:var(--accent);color:var(--accent)}
.gym h3{margin:0 0 2px;font-size:13px;display:flex;justify-content:space-between;gap:8px}
.tag{font-size:10px;text-transform:uppercase;letter-spacing:.06em;color:var(--dim)}
.meta{color:var(--dim);font-size:11px;margin-bottom:7px;font-variant-numeric:tabular-nums}
.mon{padding:4px 0;border-top:1px solid var(--line)}
.mon .sp{font-weight:600}
.mon .mv{color:var(--dim);font-size:11px}
.new{color:var(--accent)}
.ok{color:var(--ok)}.warn{color:var(--warn)}.bad{color:var(--bad)}
button{background:var(--accent);color:#fff;border:0;border-radius:6px;padding:6px 11px;
       font:inherit;font-weight:600;cursor:pointer}
button.ghost{background:transparent;color:var(--fg);border:1px solid var(--line)}
.exp{display:flex;gap:6px;align-items:center;margin-top:6px;font-size:11px;color:var(--dim)}
#msg{margin-top:8px;font-size:11px}
.cands{margin-bottom:14px}
.cand{border:1px solid var(--line);border-left:3px solid var(--line);border-radius:8px;
      background:var(--card);padding:8px 11px;margin-bottom:7px}
.cand.best{border-left-color:var(--accent)}
.cand.now{border-left-color:var(--warn)}
.cand h4{margin:0;font-size:12px;display:flex;justify-content:space-between;gap:10px;
         align-items:baseline}
.cand .num{color:var(--dim);font-size:11px;font-variant-numeric:tabular-nums}
.cand .mons{display:grid;grid-template-columns:repeat(auto-fill,minmax(148px,1fr));
            gap:6px 12px;margin-top:6px}
.cand .mons .m{border-top:1px solid var(--line);padding-top:3px;min-width:0}
.cand .mons .sp{font-size:11px;font-weight:600;display:block}
.cand .mons .mv{font-size:10px;color:var(--dim);line-height:1.35;
                overflow-wrap:anywhere}
.why{font-size:11px;color:var(--dim);margin:2px 0 8px}
.why code{color:var(--fg)}
button.tiny{padding:2px 7px;font-size:11px;font-weight:500}
</style></head><body>
<div class="bar">
  <h1>Boss Studio</h1>
  <nav><button class="tab on" id="t_build">Builder</button>
       <button class="tab" id="t_plans">Plans</button>
       <button class="tab" id="t_free">Free build</button></nav>
  <span class="tag" id="where">the nine gym fights, live</span>
</div>

<div class="wrap" id="v_build">
<div class="panel">
  <div class="sub">every control regenerates all nine fights</div>
  <div id="slot_build"></div>
  <div id="globals"></div>
  <fieldset><legend>export</legend>
    <input type="text" id="fname" value="teams_bosses_studio.json">
    <div class="exp"><label><input type="checkbox" id="ow"> overwrite if it exists</label></div>
    <div class="exp"><button id="save">Write to generated/</button>
      <button class="ghost" id="reset">Reset</button></div>
    <div id="msg"></div>
  </fieldset>
  <fieldset><legend>preset</legend>
    <div class="sub">the whole Builder in one file under generated/studio_presets/ —
      every knob, every per-fight plan and every card override. Commit it and someone
      else Loads it and gets these teams.</div>
    <select id="pload"></select>
    <div class="exp"><button class="ghost" id="pget">Load</button></div>
    <input type="text" id="pname" placeholder="name this preset">
    <div class="exp"><label><input type="checkbox" id="pow"> overwrite if it exists</label></div>
    <div class="exp"><button id="pset">Save preset</button></div>
    <div id="pmsg"></div>
  </fieldset>
</div>
<div>
  <div class="stats" id="stats"></div>
  <div class="gyms" id="gyms"></div>
  <h3 class="sect">named trainers &middot; <span id="tcount">0</span>
    <span class="tag">ships to teams_trainers.json, not exported here</span></h3>
  <div class="gyms" id="trainers"></div>
</div>
</div>

<div class="wrap" id="v_free" hidden>
<div class="panel">
  <div class="sub">pick the cores, the rest is filled to cover what they don't —
    different every time</div>
  <fieldset><legend>cores</legend>
    <div id="cores"></div>
    <datalist id="dex"></datalist>
    <div id="coresets"></div></fieldset>
  <fieldset><legend>filters</legend>
    <div class="row"><label>variations</label><input type="text" id="f_count" value="12"></div>
    <div class="row" title="how many teams any one build of your cores may take, so
      a prolific set cannot crowd out the others"><label>max per core set</label>
      <input type="text" id="f_perset" value="3"></div>
    <div class="row"><label>team size</label><input type="text" id="f_size" value="6"></div>
    <div class="row"><label>level</label><input type="text" id="f_level" value="50"></div>
    <div class="row"><label>eBST target</label><input type="text" id="f_target" value="520"></div>
    <div class="row"><label>band width</label><input type="text" id="f_spread" value="160"></div>
    <div class="row"><label>archetype</label><select id="f_arch"></select></div>
    <div class="row"><label>mode</label><select id="f_mode"></select></div>
    <div class="row"><label>tier ceiling</label><select id="f_tier"></select></div>
    <div class="row" title="every GENERATED pick must carry this type; your cores are
      kept whatever they are"><label>monotype</label>
      <select id="f_mono"></select></div>
    <div class="row"><label>generations</label><div id="f_gens" class="gens"></div></div>
    <div class="row" title="which published-set formats a pick may draw from; none
      ticked means all"><label>set formats</label>
      <div id="f_fmts" class="gens"></div></div>
    <div class="row"><label>required</label><div id="f_floors" class="gens"></div></div>
    <div class="exp"><label><input type="checkbox" id="f_mega" checked> allow megas
      (off also bans the stones and drops the mega's 100 eBST)</label></div>
    <div class="exp"><label><input type="checkbox" id="f_early"> early moves
      (keep a set's move the species has not learned yet; game-legal output
      becomes game-illegal)</label></div>
    <div class="exp"><label><input type="checkbox" id="f_explain"> explain picks
      (adds a per-variation panel showing the ranked candidates at every slot)</label></div>
    <div class="exp"><button id="fgo">Build</button>
      <button class="ghost" id="freset">Reset form</button></div>
    <div id="fmsg"></div>
  </fieldset>
  <div id="slot_free"></div>
</div>
<div><div class="cands" id="free"></div></div>
</div>

<div class="wrap" id="v_plans" hidden>
<div class="panel">
  <div class="sub">one fight at a time — what its own roster, and 54k real teams,
    argue it should be</div>
  <fieldset><legend>fight</legend>
    <select id="cf"></select>
    <div class="row" style="margin-top:8px"><label>rank by</label>
      <select id="cs" style="width:auto"><option value="evidence">evidence</option>
        <option value="strength">strength</option></select></div>
    <div class="exp"><button id="cgo">Build candidates</button></div>
    <div id="cmsg"></div>
    <div id="cwarn" class="exp" hidden><span class="warn">knobs changed since these
      were built — rebuild to refresh</span></div>
  </fieldset>
  <div id="slot_plans"></div>
  <fieldset><legend>how to read it</legend>
    <div class="why" style="margin:0">
      Candidates are built through the real generator, <b>under the Builder tab's
      current knobs</b> — otherwise a card's floors and gap would not describe the
      team you would actually generate. Changed knobs are called out above the cards.
      <br><br>
      <b>ev</b> is corpus evidence for the MODE: type lift for this fight's theme,
      plus 2 per setter and 1 per abuser already on the dev's roster.
      <b>floors</b> is what the built team actually covers.
      <b>gap</b> is eBST against the curve.<br><br>
      A plan marked <b>not this fight\u2019s mode</b> is dimmed: the fight has no real
      setter or abuser for it, or no ability setter inside its band, so the deriver will
      never choose it. You still can — it is recorded as a hand-picked plan.
      The default is the best-evidence plan <i>among those that meet their floors</i> —
      a plan that reads well and does not build is not a candidate.
      <b>use this plan</b> records it in <code>fight_plans.json</code>; the builder
      picks it up on reload.
    </div>
  </fieldset>
</div>
<div><div class="cands" id="cands"></div></div>
</div>
<script>
let S=null, timer=null, dirty=false, builtAs=null;
const $=id=>document.getElementById(id);
// Everything here renders through innerHTML, and the free-build tab is the first
// place a user types text that comes back out. Escape anything they authored.
const esc=t=>String(t==null?'':t).replace(/[&<>"']/g,
  c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
// One mon line, three callers: the Builder's nine teams, a Plans candidate card and
// a free build. It existed as two near-identical copies before the third arrived.
// `fidelity===0` means no published set stood behind this pick -- fallback() wrote
// it from the learnset -- which is a different claim from a thin set and the only
// signal a free build gives that a slot was invented rather than sourced.
// The ranked candidates behind each slot. Sent only when `explain` is on, since
// it is ~10 rows per pick per variation and nobody reading a finished team wants
// it by default. `rank` is the position in the ranking; the TAKEN row is often not
// rank 1, because take() walks this order and takes the first candidate that can
// actually do the job the floor asked for -- which is the thing this panel exists
// to make visible.
const band=(raw,b,dp)=>`${raw.toFixed(dp)}<span class="band">/${b}</span>`;
const whyPanel=tr=>`<details class="picks"><summary>why these picks</summary>
  ${tr.map(p=>`<div class="pickshead">slot ${p.slot} &middot; ${p.n} candidates
    ranked &rarr; <b>${esc(p.took||'nothing')}</b>${
      p.why?' <span class="band">'+esc(p.why)+'</span>':''}</div>
  <table><tr><th>#</th><th>species</th><th>support</th><th>played</th>
    <th>eBST gap</th><th>tier</th></tr>
  ${p.rows.map(r=>`<tr class="${r.took?'took':''}"><td>${r.rank}</td>
    <td>${esc(r.name)}</td><td>${band(r.sup,r.sup_band,1)}</td>
    <td>${band(r.marg,r.marg_band,1)}</td><td>${band(r.gap,r.gap_band,0)}</td>
    <td>${esc(r.tier)}</td></tr>`).join('')}</table>`).join('')}
</details>`;
const monLine=(m,cls,isNew,detail,editKey)=>{
  // Two different overrides a person can have put on this mon, and the row says so
  // without being opened: pinned (you put this species here) and a fixed set (you
  // named which one it must use). Both are read from CARD, so they show even on a
  // card whose editor has never been opened this session.
  const fixed=editKey&&((CARD[editKey]||{}).sets||{})[m.species];
  // The generator only flags `pinned` for a species that is not on the dev's own
  // roster -- ticking one that IS on it adds nothing for it to send back -- so a
  // held vanilla core had no mark at all. Read the tick off CARD like `fixed` does:
  // the two facts are independent (the game put it here AND you are holding it), so
  // they are two tags rather than one winning over the other.
  const held=editKey&&((CARD[editKey]||{}).keep||{})[m.species]===true;
  return `<div class="${cls}${editKey?' editable':''}${m.pinned||held?' ispin':''}${
    fixed?' isset':''}" title="${esc(m.src||m.why||'')}"${
    editKey?` data-edit="${editKey}" data-sp="${esc(m.species)}"`:''}>
  <span class="sp ${isNew?'new':''}">${esc(m.species)}</span>
  ${m.kept&&!m.pinned?'<span class="tag van">vanilla</span>':''}
  ${m.pinned||held?'<span class="tag van">pinned</span>':''}
  ${fixed?'<span class="tag van">set fixed</span>':''}
  <span class="tag">L${m.level}${m.item?' @ '+esc(m.item):''}${
    m.fidelity===0?' · no published set':m.fidelity<=1?' · thin set':''}</span>
  <div class="mv">${esc(m.moves.join(' / '))||'(engine default)'}</div>
  ${detail?`<div class="why">${[
    m.ability?esc(m.ability):null,
    m.kept?'your core':esc(m.why||''),
    m.support==null?null:(m.support>0
      ?`on ${m.support}% of real teams with your cores`
      :`no team with your cores ran it · ${m.marginal}% of all teams`)
   ].filter(Boolean).join(' · ')}</div>`:''}</div>`;};
// What a candidate set was built under. Anything that changes it makes the cards on
// screen a picture of a build nobody would get now.
const sig=()=>JSON.stringify(get())+'|'+$('cf').value+'|'+$('cs').value;
function checkStale(){ if(builtAs) $('cwarn').hidden = sig()===builtAs; }
// The plan a fight is built under, per card. ONE place it lives: the selects are
// re-rendered with the cards on every build, so reading the choice back off the DOM
// would lose it the moment a build replaced the node. The gyms are a full list
// because the generator reads ARCHETYPE[i]/MODE[i]; the trainers are sparse.
let PLAN={gym:[],tr:{}};
// Per-card, per-species overrides: {cardKey: {keep:{SPECIES:bool}, sets:{SPECIES:label}}}
let CARD={};
// The last build's mons, by card key + species, so an editor opened after the
// fact shows the set and level that build actually used.
let MONS={};
const cardOf=fk=>CARD[fk]=CARD[fk]||{keep:{},sets:{}};
const get=()=>{
  const o={level_mode:$('level_mode').value,TRAINER_PLANS:PLAN.tr,PICKS:CARD,
    SET_FORMATS:[...$('setfmt').querySelectorAll('input:checked')].map(e=>e.value)};
  for(const k in S.meta) o[k]=+$('s_'+k).value;
  for(const k of ['TARGET','SPREAD','THEME'])
    o[k]=[...Array(9).keys()].map(i=>{
      const el=$(k+'_'+i); return (k==='TARGET'||k==='SPREAD')?+el.value:el.value;});
  o.ARCHETYPE=PLAN.gym.map(p=>p.a);
  o.MODE=PLAN.gym.map(p=>p.m);
  return o;
};
// The inverse of get(), and it has to stay the exact inverse: get() is what the
// generator is handed, so a key setAll forgets is a knob that silently keeps YOUR
// value while claiming to have loaded someone else's preset. The smoke test asserts
// the round trip rather than trusting this to be kept in step by hand.
// Everything is shape-checked on the way in for the same reason buildRestore() does
// it -- a preset is a file a person can edit, and a bad ARCHETYPE reaches the
// generator as a dict key.
function setAll(o){
  if(!o||typeof o!=='object') return false;
  if(o.level_mode&&S.level_modes.includes(o.level_mode)) $('level_mode').value=o.level_mode;
  for(const k in S.meta) if(o[k]!=null&&isFinite(o[k])){
    $('s_'+k).value=o[k];
    if($('val_'+k)) $('val_'+k).textContent=$('s_'+k).value;
  }
  for(const k of ['TARGET','SPREAD','THEME']) if(Array.isArray(o[k]))
    o[k].forEach((v,i)=>{const el=$(k+'_'+i); if(el&&v!=null) el.value=v;});
  const fmts=new Set(Array.isArray(o.SET_FORMATS)?o.SET_FORMATS:[]);
  $('setfmt').querySelectorAll('input').forEach(e=>{e.checked=fmts.has(e.value);});
  if(Array.isArray(o.ARCHETYPE)&&Array.isArray(o.MODE))
    PLAN.gym=PLAN.gym.map((p,i)=>(
      {a:S.archetypes.includes(o.ARCHETYPE[i])?o.ARCHETYPE[i]:p.a,
       m:S.modes.includes(o.MODE[i])?o.MODE[i]:p.m}));
  PLAN.tr=(o.TRAINER_PLANS&&typeof o.TRAINER_PLANS==='object')?o.TRAINER_PLANS:{};
  CARD=(o.PICKS&&typeof o.PICKS==='object')?o.PICKS:{};
  buildSave();               // a loaded preset survives a reload like anything else
  return true;
}
async function presetList(sel){
  const d=await (await fetch('/api/presets')).json();
  const now=sel||$('pload').value;
  $('pload').innerHTML=(d.presets||[]).map(p=>
    `<option value="${esc(p.name)}" ${p.name===now?'selected':''}>${esc(p.name)}${
      p.saved?' · '+esc(p.saved.slice(0,10)):''}</option>`).join('')
    ||'<option value="">(none saved yet)</option>';
}
const deb=()=>{clearTimeout(timer);timer=setTimeout(go,120);};
// A rebuild is ~2s for 27 fights, and every tick, every dropdown and every knob asks
// for one. Without a guard a person clicking four boxes gets four concurrent builds
// racing to write the same DOM, and the last response to ARRIVE wins rather than the
// last one asked for. One in flight at a time, with a single trailing re-run that
// collapses however many changes landed while it was busy.
let busy=false, pending=false, lastSha=null;
async function go(){
  if(busy){ pending=true; return; }
  busy=true; $('v_build').classList.add('busy');
  try{
    const r=await fetch('/api/generate',{method:'POST',body:JSON.stringify(get())});
    const d=await r.json();
    if(d.error){$('stats').innerHTML='<span class="bad">'+d.error+'</span>';return;}
    render(d);
  } finally {
    busy=false; $('v_build').classList.remove('busy');
    if(pending){ pending=false; go(); }
  }
}
function render(d){
  MONS={};
  lastSha=d.sha||null;
  const remember=(fk,mons)=>mons.forEach(m=>{MONS[fk+'|'+m.species]=m;});
  const cls=v=>v<=2?'ok':v<=6?'warn':'bad';
  $('stats').innerHTML=[
    ['curve MAD',d.mad+' BST',cls(d.mad)],
    ['variety pctile',d.variety.pctile+'%',d.variety.pctile<5?'bad':'ok'],
    ['spread vs real',d.variety.got+' / '+d.variety.mean,''],
    ['megas',d.gyms.filter(g=>g.mega).length+'/9',''],
    ['floors met',d.gyms.reduce((a,g)=>a+g.met,0)+'/'+
       d.gyms.reduce((a,g)=>a+Object.keys(g.floors).length,0),''],
    ['validator',d.errors.length?d.errors.length+' errors':'clean',
       d.errors.length?'bad':'ok'],
  ].map(([l,v,c])=>`<div class="stat"><span>${l}</span><b class="${c}">${v}</b></div>`).join('');
  $('gyms').innerHTML=d.gyms.map((g,i)=>
    (remember('g'+i,g.mons),
     teamCard(g,`Boss ${i+1} · ${esc(g.theme)}`,Object.values(S.shipped)[i]||[],
              planPick('gym',i,g.archetype,g.mode),'g'+i,i))).join('');
  // The named non-gym trainers, from a different generator and a different shipped
  // file. Reported beside the gyms because "did this regenerate break anything" is
  // one question about all of them, never merged into the gym stats above -- the
  // variety null is computed for nine teams and the curve MAD is the gym ladder.
  const tr=d.trainers||[];
  $('tcount').textContent=tr.length;
  $('trainers').innerHTML=tr.map(t=>(remember('t'+t.slot,t.mons),teamCard(t,
    `${esc(t.who)}${t.dynamic?' <span class="tag">scales</span>':''}`,null,
    planPick('tr',t.slot,t.archetype,t.mode),'t'+t.slot,t.slot))).join('');
}
const opts=(vals,sel,blank)=>vals.map(v=>
  `<option value="${v}" ${v===sel?'selected':''}>${v||blank||'—'}</option>`).join('');
// Per-card plan. A gym gets no blank archetype -- the generator indexes ARCHETYPE[i]
// straight into the role table and "" is not a key there -- while a trainer may
// genuinely have none, which is what the flat presence quota is.
const planPick=(kind,slot,a,m)=>`<div class="plan">
  <select data-plan="${kind}" data-slot="${slot}" data-f="a">${
    opts(kind==='tr'?[''].concat(S.archetypes):S.archetypes,a||'','flat quota')}</select>
  <select data-plan="${kind}" data-slot="${slot}" data-f="m">${
    opts(S.modes,m||'','no mode')}</select></div>`;
// Per-mon controls open on CLICK, one row at a time. They used to sit in a row under
// every name: 27 cards x 6 mons is 162 always-visible checkboxes and set menus, for
// something used on a handful of them, and it buried the moves the card exists to
// show. The row itself is the affordance now.
//
// Changing the species is expressed as the two picks that already work -- drop the
// one that is there, pin the one you want -- so it needs no new server machinery and
// obeys the same rules (a swapped-in mon is `pinned`, not `vanilla`).
const monEditor=(fk,m)=>`<div class="edit">
  <label>species<input list="dex" value="${esc(m.species)}"
    data-swap="${fk}" data-sp="${esc(m.species)}" spellcheck="false"></label>
  <label>set<select data-set="${fk}" data-sp="${esc(m.species)}" data-lv="${m.level}">
    <option value="">${esc(m.src||'whatever ranks best')}</option></select></label>
  <label class="keep"><input type="checkbox" data-pin="${fk}"
    data-sp="${esc(m.species)}" ${m.kept?'checked':''}>keep this Pokémon on the fight</label>
</div>`;
// One Builder card, for a gym and for a named trainer alike.
// What this card has been told to do that the globals did not ask for. Counted, not
// just flagged: "edited" alone makes you open the card to find out what you changed,
// and after a reload that is every card you ever touched.
const dirtyOf=(fk,i)=>{
  const c=CARD[fk]||{};
  const mons=Object.keys(c.keep||{}).length+Object.keys(c.sets||{}).length;
  const p=fk[0]==='g'?PLAN.gym[i]:PLAN.tr[fk.slice(1)];
  const plan=fk[0]==='g'
    ? !!(p&&(p.a!==S.lists.ARCHETYPE[i]||(p.m||'')!==(S.lists.MODE[i]||'')))
    : !!p;
  return (mons||plan)?{mons,plan}:null;
};
const teamCard=(g,title,was,pick,fk,i)=>{
  const gap=g.ebst-g.target, j=g.judge, d=fk?dirtyOf(fk,i):null;
  return `<div class="gym${d?' dirty':''}"><h3><span>${title}${d?
      ` <span class="tag edited">edited${d.plan?' · plan':''}${
        d.mons?' · '+d.mons+' mon'+(d.mons>1?'s':''):''}</span>`:''}</span>
    <span>${pick||''}</span></h3>
    <div class="meta">eBST <b class="${Math.abs(gap)<=3?'ok':Math.abs(gap)<=12?'warn':'bad'}">${g.ebst}</b>/${g.target}
      · lv ${g.level}${g.ace?' · ace '+esc(String(g.ace)):''} · EV off ${g.offence}%${
      g.ev_target==null?'':` <span class="${Math.abs(g.offence-g.ev_target)<=12?'ok':'warn'}">(want ${g.ev_target}%)</span>`}
      · floors ${g.met}/${Object.keys(g.floors).length}
      · mega ${esc(g.mega||'—')}</div>
    <div class="meta">unresisted <b class="${j.nobody_resists>4?'bad':'ok'}">${
      j.nobody_resists}</b> · repeats <b class="${j.dup_types?'bad':'ok'}">${
      j.dup_types}</b> · worst shared ${j.worst_shared} · hits ${j.off_se}/18</div>
    ${g.mons.map(m=>monLine(m,'mon',!!was&&!was.includes(m.species),true,
                            fk&&!m.dynamic?fk:'')).join('')}
    <div class="exp"><button class="tiny ${d?'':'ghost'}" data-reset="${fk}"${
      d?'':' disabled'}>reset this card to the global settings</button></div>
    </div>`;}
// Candidates are built through the real generator under the BUILDER's knobs -- they
// have to be, or a card's floors and gap describe a team you would not get. That is
// invisible once the two tabs are apart, so say which knobs are not at their defaults.
function knobDiff(o,fight){
  const out=[];
  for(const k in S.meta) if(+o[k]!==+S.scalars[k]) out.push(k+' '+o[k]);
  if(o.level_mode!==S.level_mode) out.push('ladder '+o.level_mode);
  const i=S.fights.findIndex(f=>f.id===fight);
  if(i>=0&&S.fights[i].kind==='gym')
    for(const k of ['TARGET','SPREAD','THEME'])
      if(String(o[k][i])!==String(S.lists[k][i]))
        out.push('gym '+(i+1)+' '+k+' '+o[k][i]);
  return out;
}
async function candidates(){
  const fight=$('cf').value, sort=$('cs').value, o=get();
  $('cmsg').innerHTML='<span class="tag">building…</span>';
  const q=new URLSearchParams({fight,sort,settings:JSON.stringify(o)});
  const d=await (await fetch('/api/candidates?'+q)).json();
  if(d.error){$('cmsg').innerHTML='<span class="bad">'+d.error+'</span>';return;}
  const diff=knobDiff(o,fight);
  builtAs=sig(); $('cwarn').hidden=true;
  $('cmsg').innerHTML='<span class="tag">'+d.plans.length+' candidates</span>';
  const knobs=diff.length
    ?`<div class="why"><span class="warn">built under changed Builder knobs:</span>
       <code>${diff.join('</code> · <code>')}</code> — the floors and gaps below are
       for those settings, not the defaults.</div>`
    :`<div class="why">built under the default Builder knobs.</div>`;
  const rej=Object.entries(d.rejected).map(([m,w])=>`${m} ${d.evidence[m]} (${w})`);
  $('cands').innerHTML=knobs+`<div class="why"><b>${d.label}</b> — ${d.kind},
    gym-${d.stage+1} band, theme <code>${d.theme||'—'}</code>, target ${d.target}.
    keeps <code>${d.spine.join(' ')||'—'}</code>
    ${d.core.length?'· spine <code>'+d.core.join(' ')+'</code>':''}
    ${d.warn?'<br><span class="warn">'+d.warn+'</span>':''}
    ${rej.length?'<br>not proposed: '+rej.join('; '):''}</div>`
    +d.plans.map((p,i)=>{
      const plan=(p.archetype||'flat quota')+(p.mode?' + '+p.mode:'');
      const cls=(i===0?'cand best':(p.incumbent?'cand now':'cand'))
                +(p.gated?' gated':'');
      return `<div class="${cls}"><h4><span>${plan}
        ${i===0?'<span class="tag">default</span>':''}
        ${p.incumbent?'<span class="tag">today</span>':''}
        ${p.gated?'<span class="tag bad">not this fight\u2019s mode: '
                  +p.gate_why+'</span>':''}</span>
        <span class="num">ev ${p.evidence} ·
          <span class="${p.met<p.need?'bad':'ok'}">floors ${p.met}/${p.need}</span>
          ${p.missed.length?'('+p.missed.join(', ')+')':''} ·
          gap <span class="${Math.abs(p.gap)<=3?'ok':Math.abs(p.gap)<=12?'warn':'bad'}">${p.gap>0?'+':''}${p.gap}</span>
          · unresisted <span class="${p.judge.nobody_resists>4?'bad':'ok'}">${
            p.judge.nobody_resists}</span> · repeats <span class="${
            p.judge.dup_types?'bad':'ok'}">${p.judge.dup_types}</span> · hits ${
            p.judge.off_se}/18
        </span></h4>
        <div class="mons">${p.mons.map(m=>monLine(m,'m',!m.kept,true)).join('')}</div>
        <div class="exp"><button class="tiny ghost"
          onclick='usePlan(${JSON.stringify(JSON.stringify(
            {fight:d.fight,archetype:p.archetype,mode:p.mode,evidence:p.evidence,
             gap:p.gap,floors_met:p.met+"/"+p.need}))})'>use this plan</button></div>
        </div>`;}).join('');
}
async function usePlan(payload){
  const r=await fetch('/api/plan',{method:'POST',body:payload});
  const d=await r.json();
  $('cmsg').innerHTML=d.error?`<span class="bad">${d.error}</span>`
    :`<span class="ok">wrote ${d.ok} — reload to build on it</span>`;
}
// The free form is the only state in this page worth keeping: the Builder's knobs
// are answered by /api/state every load, but nobody wants to retype six species and
// eight filters after a server restart. localStorage rather than a file on the
// server, because this is one person's page and per-browser is the right scope.
//
// #globals is deliberately excluded. show() APPENDS that container into whichever
// tab is open, so while the free tab is active the Builder's sliders are physically
// inside #v_free -- persisting them here would quietly restore generator knobs on
// every load and make the Builder disagree with its own defaults.
// Form persistence, two callers: the free-build form and the Builder's knobs. One
// pair of helpers rather than two, because the only thing that differs is WHICH
// controls belong to the form.
const FREE_KEY='bossStudio.free.v1', BUILD_KEY='bossStudio.build.v1',
      PLAN_KEY='bossStudio.plan.v1';
const freeControls=()=>[...$('v_free').querySelectorAll('input,select')]
  .filter(el=>!el.closest('#globals'));
// #globals is ONE container that moves between sidebars, so it is addressed directly
// rather than through #v_build -- while the Plans tab is up it is not inside
// #v_build at all and a subtree query would silently save nothing. `ow` is left out
// on purpose: an overwrite flag that survives a reload is a foot-gun, not a setting.
const buildControls=()=>[...$('globals').querySelectorAll('input,select'),
                         ...$('per').querySelectorAll('input,select'), $('fname')];
// Checkbox groups (#f_gens, #f_floors) are built without ids, so they key off their
// container plus their value.
const ctlKey=el=>el.id||((el.closest('[id]')||{}).id+':'+el.value);
function saveForm(key,controls){
  const st={};
  for(const el of controls()) st[ctlKey(el)]=el.type==='checkbox'?el.checked:el.value;
  try{localStorage.setItem(key,JSON.stringify(st));}catch(e){}
}
function restoreForm(key,controls){
  let st=null;
  try{st=JSON.parse(localStorage.getItem(key)||'null');}catch(e){}
  if(!st) return false;
  let n=0;
  for(const el of controls()){
    const k=ctlKey(el);
    if(!(k in st)) continue;            // a control added since the save: leave default
    if(el.type==='checkbox') el.checked=!!st[k]; else el.value=st[k];
    n++;
  }
  return n>0;
}
const freeSave=()=>saveForm(FREE_KEY,freeControls);
// PLAN is not a form control, so it rides along with the knobs rather than under a
// save of its own that could fall out of step with them.
function buildSave(){
  saveForm(BUILD_KEY,buildControls);
  try{localStorage.setItem(PLAN_KEY,JSON.stringify({PLAN,CARD}));}catch(e){}
}
const freeRestore=()=>restoreForm(FREE_KEY,freeControls);
// Restoring knobs means the Builder no longer shows what the repo ships, so say so
// -- a silently-restored TARGET or MODE is a picture of a build nobody else would
// get. Reset has to CLEAR the save, not just reload: with persistence a reload
// replays the saved form, and a Reset button that resets nothing is worse than none.
function buildRestore(){
  let saved=null;
  try{saved=JSON.parse(localStorage.getItem(PLAN_KEY)||'null');}catch(e){}
  // The key held a bare PLAN before the per-mon picks existed; accept both rather
  // than silently discarding someone's saved per-fight plans on the first reload.
  const plan=saved&&saved.PLAN?saved.PLAN:saved;
  if(saved&&saved.CARD&&typeof saved.CARD==='object') CARD=saved.CARD;
  // Shape-check rather than trust: a saved PLAN from an older page could be missing
  // halves, and a bad ARCHETYPE entry reaches the generator as a dict key.
  if(plan&&Array.isArray(plan.gym)&&plan.gym.length===9){
    PLAN.gym=plan.gym.map((p,i)=>({a:S.archetypes.includes(p&&p.a)?p.a:PLAN.gym[i].a,
                                   m:S.modes.includes(p&&p.m)?p.m:PLAN.gym[i].m}));
  }
  if(plan&&plan.tr&&typeof plan.tr==='object') PLAN.tr=plan.tr;
  const knobs=restoreForm(BUILD_KEY,buildControls);
  if(!knobs&&!plan) return;
  for(const k in S.meta) if($('val_'+k)) $('val_'+k).textContent=$('s_'+k).value;
  $('msg').innerHTML='<span class="warn">restored your saved knobs</span> — '
    +'Reset returns to the shipped values.';
}
function freeSpec(){
  return {cores:[...Array(6).keys()].map(i=>$('core_'+i).value.trim()).filter(Boolean),
    count:+$('f_count').value, size:+$('f_size').value, level:+$('f_level').value,
    target:+$('f_target').value, spread:+$('f_spread').value,
    per_set:+$('f_perset').value,
    set_filter:SETFILTER,
    archetype:$('f_arch').value, mode:$('f_mode').value,
    tier_ceiling:$('f_tier').value,
    // A single type, sent as the list the pool filter already takes. Applies to
    // generated picks only -- a core you typed is a core you chose, and silently
    // dropping it for being off-type would be answering a different question.
    types:$('f_mono').value?[$('f_mono').value]:[],
    explain:$('f_explain').checked, early_moves:$('f_early').checked,
    set_formats:[...document.querySelectorAll('#f_fmts input:checked')].map(e=>e.value),
    gens:[...document.querySelectorAll('#f_gens input:checked')].map(
      el=>isNaN(+el.value)?el.value:+el.value),
    drop_floors:[...document.querySelectorAll('#f_floors input:not(:checked)')].map(
      el=>el.value),
    allow_mega:$('f_mega').checked,
    settings:get()};
}
// {SPECIES: [labels]} -- empty or missing means "any set", which is what an
// untouched picker means. Rebuilt from the DOM so it cannot drift from the boxes.
let SETFILTER={};
function readSetFilter(){
  SETFILTER={};
  for(const box of document.querySelectorAll('#coresets input:checked')){
    (SETFILTER[box.dataset.sp]=SETFILTER[box.dataset.sp]||[]).push(box.value);}
  freeSave();
}
async function loadCoreSets(){
  const names=[...Array(6).keys()].map(i=>$('core_'+i).value.trim()).filter(Boolean);
  const keep=SETFILTER; SETFILTER={};
  const blocks=[];
  for(const n of names){
    const r=await fetch('/api/sets',{method:'POST',body:JSON.stringify(
      {species:n,level:+$('f_level').value,allow_mega:$('f_mega').checked})});
    const d=await r.json();
    if(!d.species){blocks.push(`<div class="sub">${esc(n)} — not in this dex</div>`);
                   continue;}
    const on=new Set(keep[d.species]||[]);
    blocks.push(`<details class="setpick"><summary><span class="grphead">${
      esc(d.species)} sets</span><span class="tag">${d.sets.length}</span>
      <span class="sub">tick to restrict; none ticked = any</span></summary>
      ${d.sets.map(x=>`<label class="setrow">
        <input type="checkbox" data-sp="${esc(d.species)}" value="${esc(x.label)}"${
          on.has(x.label)?' checked':''}>
        <span class="setname">${esc(x.setname)}</span>
        <span class="tag">${esc(x.fmt)}${x.source==='stats'?' · usage':''}</span>
        <span class="sub">${x.item?esc(x.item)+' · ':''}${esc(x.ability||'')} · ${
          esc(x.moves.join(' / '))}</span></label>`).join('')}</details>`);
  }
  $('coresets').innerHTML=blocks.join('');
  readSetFilter();
}
async function freeBuild(){
  $('fmsg').innerHTML='building…';
  const r=await fetch('/api/free',{method:'POST',body:JSON.stringify(freeSpec())});
  const d=await r.json();
  if(d.error){$('fmsg').innerHTML=`<span class="bad">${esc(d.error)}</span>`;
              $('free').innerHTML='';return;}
  $('fmsg').innerHTML=`<span class="${d.distinct<d.asked?'warn':'ok'}">${
    d.distinct} distinct</span>`
    +(d.requested>d.cap?` — asked ${d.requested}, capped at ${d.cap}`:'')
    +(d.distinct<d.asked?` — only ${d.distinct} exist under these filters (${
      d.tried} builds for ${d.asked})`:'')
    +(d.core_sets>1?` across ${d.core_sets} core sets`:
      (d.cores.length?' · your cores build only one way under these filters':''))
    +(d.cores.length?` · of ${d.basis} real teams that contain your cores`:'');
  const byseed={};
  for(const v of d.variations) byseed[v.seed]=v;
  const card=v=>{
    const j=v.judge;
    const plan=v.plan?`${esc(v.plan.archetype)}${
      v.plan.mode?' + '+esc(v.plan.mode):''}`:'';
    return `<div class="cand best"><h4><span>variation ${v.seed}${
      plan?` <span class="tag accent">${plan}</span>`:''}</span>
      <span class="num">unresisted <span class="${j.nobody_resists>4?'bad':'ok'}">${
        j.nobody_resists}</span> · repeats <span class="${
        j.dup_types?'bad':'ok'}">${j.dup_types}</span> · hits ${j.off_se}/18</span></h4>
      <div class="mons">${v.mons.map(m=>monLine(m,'m',!m.kept,true)).join('')}</div>
      ${v.notes.map(n=>`<div class="sub">${esc(n)}</div>`).join('')}
      <div class="exp"><button class="tiny ghost"
        onclick="this.parentNode.nextElementSibling.hidden=!this.parentNode.nextElementSibling.hidden">
        Showdown paste</button></div>
      <pre class="paste" hidden>${esc(v.paste)}</pre>
      ${v.trace?whyPanel(v.trace):''}</div>`;};
  // Grouped by what YOUR cores are running, so the list reads "here is this build of
  // the core, and here are the teams around it" rather than interleaving them.
  // <details> rather than a JS toggle: it collapses natively, keeps its own state
  // per element, and the summary stays readable when shut. The first group opens so
  // the page is never a wall of closed rows.
  $('free').innerHTML=d.groups.map((g,i)=>{
    const label=g.core.length?'core set '+String.fromCharCode(65+i):'teams';
    const line=g.core.length?g.core.map(m=>
      `${esc(m.species)}${m.item?' @ '+esc(m.item):''}${
        m.ability?' · '+esc(m.ability):''} · ${esc(m.moves.join(' / '))}`
      ).join(' // '):'no cores · every slot generated';
    // Where the set came from. `fidelity 0` means nothing published fit and the set
    // was written from the learnset, which is a different claim from a tier name.
    const prov=g.core.map(m=>m.fidelity===0?'no published set':esc(m.src))
      .join(' // ');
    return `<details class="grp"${i?'':' open'}>
      <summary><span class="grphead">${label}</span>
        <span class="tag">${g.seeds.length} team${g.seeds.length>1?'s':''}</span>
        <span class="coreline">${line}</span>
        <span class="prov">${prov}</span></summary>
      ${g.seeds.map(sd=>card(byseed[sd])).join('')}</details>`;}).join('');
}
async function init(){
  S=await (await fetch('/api/state')).json();
  // One fieldset per GROUPS entry, in the server's order. Every key is a slider off
  // S.meta except the few that are not ranges, which name themselves here; a key
  // with no renderer would be a knob nobody can reach, so it throws.
  const slider=k=>{
    const [kind,lo,hi,step,help]=S.meta[k], v=S.scalars[k];
    return `<div class="row" title="${esc(help)}"><label>${k}</label>
      <span class="v" id="val_${k}">${v}</span>
      <input type="range" id="s_${k}" min="${lo}" max="${hi}" step="${step}" value="${v}"></div>`;
  };
  const CTL={
    level_mode:()=>`<div class="row" title="${esc(
      'which level ladder the nine fights are built on')}">
      <label>level ladder</label><select id="level_mode">${S.level_modes.map(m=>
        `<option ${m===S.level_mode?'selected':''}>${m}</option>`).join('')}
      </select></div>`,
    SET_FORMATS:()=>`<div class="row" title="${esc(
      'which published-set formats a build may draw from. This filters the SETS, '
      +'not the species -- a different question from a tier ceiling. Tick none for '
      +'all of them.')}"><label>set formats</label></div>
      <div id="setfmt" class="gens">${S.set_tiers.map(t=>
        `<label><input type="checkbox" value="${t}"> ${t}</label>`).join('')}</div>`,
    // Nested inside its group rather than a card of its own: the nine rows say WHEN
    // each fight happens -- its theme, the power it is aimed at and how wide -- which
    // is the badge-by-badge half of the same question the sliders above answer
    // globally. Filled by the block below, which needs the table to exist first.
    per_fight:()=>`<fieldset id="perwrap"><legend>per fight</legend>
      <table id="per"></table></fieldset>`,
  };
  $('globals').innerHTML=S.groups.map(([label,keys])=>`<fieldset>
    <legend>${esc(label)}</legend>${keys.map(k=>{
      if(CTL[k]) return CTL[k]();
      if(!S.meta[k]) throw new Error('no control for '+k);
      return slider(k);}).join('')}</fieldset>`).join('');
  // archetype and mode are chosen ON THE CARD, so they are not here as well: two
  // controls for one value is two states and a sync bug the first time they disagree.
  $('per').innerHTML='<tr><th></th><th>theme</th><th>tgt</th><th>±</th></tr>'
    +[...Array(9).keys()].map(i=>`<tr><td class="tag">${i+1}</td>
      <td><select id="THEME_${i}">${opts(S.types,S.lists.THEME[i])}</select></td>
      <td><input type="text" id="TARGET_${i}" value="${S.lists.TARGET[i]}" style="width:46px"></td>
      <td><input type="text" id="SPREAD_${i}" value="${S.lists.SPREAD[i]}" style="width:44px"></td>
      </tr>`).join('');
  PLAN.gym=[...Array(9).keys()].map(i=>
    ({a:S.lists.ARCHETYPE[i],m:S.lists.MODE[i]||''}));
  $('cf').innerHTML=S.fights.map(f=>
    `<option value="${f.id}">${f.label} · ${f.kind}</option>`).join('');
  // The global knobs are ONE container that moves between the two sidebars, not a
  // copy in each: duplicated controls mean duplicated ids, two states and a sync bug
  // the first time they disagree. Moving the node keeps its listeners and its values.
  // Naming a file is not a knob: these live inside #v_build and so get the same
  // listener, but none of them changes what a team is.
  const NOBUILD=new Set(['fname','ow','pname','pow','pload']);
  const onKnob=e=>{
    const k=e.target.id.replace(/^s_/,'');
    if($('val_'+k))$('val_'+k).textContent=e.target.value;
    buildSave();
    if(NOBUILD.has(e.target.id))return;
    checkStale();
    // Regenerating the nine while the Plans tab is up is work nobody asked for, so
    // it is deferred to the moment you go back to it.
    if($('v_build').hidden) dirty=true; else deb();
  };
  $('v_build').querySelectorAll('input,select').forEach(
    el=>el.addEventListener('input',onKnob));
  // Delegated: the cards (and their selects) are replaced wholesale by every build,
  // so a listener bound to a select would be thrown away with it.
  for(const host of ['gyms','trainers']) {
    $(host).addEventListener('change',e=>{
      const el=e.target, d=el.dataset;
      if(d.plan){
        if(d.plan==='gym') PLAN.gym[+d.slot][d.f]=el.value;
        else (PLAN.tr[d.slot]=PLAN.tr[d.slot]||['',''])[d.f==='a'?0:1]=el.value;
      } else if(d.pin!==undefined){
        cardOf(d.pin).keep[d.sp]=el.checked;
      } else if(d.swap!==undefined){
        const to=el.value.trim().toUpperCase(), from=d.sp;
        if(!to||to===from){ el.value=from; return; }
        if(!S.dex.includes(to)){
          el.setCustomValidity?el.setCustomValidity(''):0;
          el.value=from; $('msg').innerHTML=
            `<span class="bad">${esc(to)} is not in this game's dex</span>`;
          return;
        }
        const c=cardOf(d.swap);
        c.keep[from]=false; c.keep[to]=true;
        // The set was chosen for the species that is leaving; it means nothing to
        // the one arriving, and a stale label would silently match no set at all.
        delete c.sets[from];
      } else if(d.set!==undefined){
        const c=cardOf(d.set);
        if(el.value) c.sets[d.sp]=el.value; else delete c.sets[d.sp];
      } else return;
      buildSave(); checkStale(); deb();
    });
    // The set list is per species AND per level, so it is fetched when you open the
    // menu rather than shipped with all 27 cards -- 162 mons' worth of set lists is
    // a payload nobody reads. `focus` fires before the list is drawn.
    $(host).addEventListener('focusin',async e=>{
      const el=e.target, d=el.dataset;
      if(d.set===undefined||el.dataset.loaded) return;
      el.dataset.loaded='1';
      const r=await fetch('/api/sets',{method:'POST',body:JSON.stringify(
        {species:d.sp,level:+String(d.lv).replace(/[^0-9]/g,'')||50})});
      const got=await r.json();
      const cur=(CARD[d.set]||{}).sets||{};
      el.innerHTML=`<option value="">whatever ranks best</option>`
        +(got.sets||[]).map(x=>`<option value="${esc(x.label)}"${
          cur[d.sp]===x.label?' selected':''}>${esc(x.label)}</option>`).join('');
    });
    $(host).addEventListener('click',e=>{
      const fk=e.target.dataset&&e.target.dataset.reset;
      if(fk){ delete CARD[fk]; buildSave(); deb(); return; }
      // Inside an open editor is not a click ON the row.
      if(e.target.closest('.edit')) return;
      const row=e.target.closest('.mon.editable');
      if(!row) return;
      const open=row.querySelector('.edit');
      if(open){ open.remove(); row.classList.remove('open'); return; }
      // One at a time: two open editors is two species inputs a person can half-fill.
      for(const o of $(host).querySelectorAll('.mon.open')){
        o.classList.remove('open');
        const e2=o.querySelector('.edit'); if(e2) e2.remove();
      }
      row.classList.add('open');
      row.insertAdjacentHTML('beforeend', monEditor(row.dataset.edit, MONS[
        row.dataset.edit+'|'+row.dataset.sp]||{species:row.dataset.sp,level:50}));
    });
  }
  for(const id of ['cf','cs']) $(id).addEventListener('input',checkStale);
  const show=v=>{
    for(const n of ['build','plans','free']){
      $('v_'+n).hidden=(n!==v); $('t_'+n).classList.toggle('on',n===v);}
    $('slot_'+v).appendChild($('globals'));
    // The globals apply to a free build too; these nine gym rows do not, so they
    // ride along hidden rather than offering a target nothing downstream reads.
    $('perwrap').hidden = v!=='build';
    $('where').textContent={build:'the nine gym fights, live',
      plans:'27 fights · '+(Object.keys(S.plans).length||'no')+' plans recorded',
      free:'build around your own cores'}[v];
    if(v==='build'&&dirty){dirty=false;go();}
  };
  $('t_build').onclick=()=>show('build');
  $('t_plans').onclick=()=>show('plans');
  $('t_free').onclick=()=>show('free');
  $('fgo').onclick=freeBuild;
  // Delegated, so it also catches the core boxes and checkboxes that init() builds.
  // Delegated on the tab, never bound per element. The core boxes, the generation
  // ticks and the set pickers are all created later in init() or at runtime, so
  // addEventListener on their ids here would hit null and abort the whole of init()
  // -- which is exactly what happened: the cores fieldset rendered empty because
  // $('core_0') did not exist yet when this ran.
  for(const ev of ['input','change']) $('v_free').addEventListener(ev,e=>{
    if(e.target.closest('#globals')) return;
    if(e.target.closest('#coresets')){readSetFilter(); return;}
    freeSave();
    // The cores, the level and the mega rule all change which sets are legal.
    if(ev==='change'&&/^(core_[0-5]|f_level|f_mega)$/.test(e.target.id))
      loadCoreSets();});
  $('freset').onclick=()=>{
    try{localStorage.removeItem(FREE_KEY);}catch(e){}
    location.reload();};
  $('cgo').onclick=candidates;
  $('cores').innerHTML=[...Array(6).keys()].map(i=>
    `<div class="row"><label>${i+1}</label>
     <input type="text" list="dex" id="core_${i}" placeholder="optional"></div>`).join('');
  $('dex').innerHTML=S.dex.map(n=>`<option value="${n}">`).join('');
  // "no preference" is a THIRD state, not a blank: mode's "" already means "this
  // team deliberately has no mode", which is a different instruction from "sweep
  // them for me", and collapsing the two would make one of them unsayable.
  const optsAny=(vals,sel,blank)=>
    `<option value="${S.any}"${sel===S.any?' selected':''}>no preference</option>`
    +opts(vals,sel,blank);
  $('f_arch').innerHTML=optsAny(S.archetypes,'balance');
  $('f_mode').innerHTML=optsAny(S.modes,'','none');
  $('f_tier').innerHTML=opts([''].concat(S.tiers),'');
  $('f_mono').innerHTML=opts([''].concat(S.types),'','any type');
  $('f_fmts').innerHTML=S.set_tiers.map(t=>
    `<label><input type="checkbox" value="${t}"> ${t}</label>`).join('');
  $('f_gens').innerHTML=S.generations.map(g=>
    `<label><input type="checkbox" value="${g}"> ${g}</label>`).join('');
  // Checked = required, which is what the generator does on its own. Unticking one
  // drops the floor; it does not forbid the role.
  $('f_floors').innerHTML=S.floor_roles.map(r=>
    `<label><input type="checkbox" value="${r}" checked> ${r}</label>`).join('');
  freeRestore();
  loadCoreSets();
  buildRestore();
  $('reset').onclick=()=>{
    try{localStorage.removeItem(BUILD_KEY);localStorage.removeItem(PLAN_KEY);}catch(e){}
    location.reload();};
  presetList();
  // Load is the half that matters: it applies the file, rebuilds, and then says
  // whether the teams it got are the ones the preset recorded. Without that last
  // step "loaded" only means "the knobs moved", which is not what was asked for.
  $('pget').onclick=async()=>{
    const name=$('pload').value;
    if(!name) return void($('pmsg').innerHTML='<span class="warn">nothing saved yet</span>');
    const d=await (await fetch('/api/preset?name='+encodeURIComponent(name))).json();
    if(d.error) return void($('pmsg').innerHTML='<span class="bad">'+esc(d.error)+'</span>');
    if(!setAll(d.settings))
      return void($('pmsg').innerHTML='<span class="bad">that preset has no settings</span>');
    $('pmsg').innerHTML='rebuilding…';
    await go();
    const same=d.sha&&lastSha&&d.sha===lastSha;
    $('pmsg').innerHTML=same
      ? `<span class="ok">loaded ${esc(d.name)} — teams match its fingerprint `
        +`${esc(d.sha)}</span>${d.note?' · '+esc(d.note):''}`
      : `<span class="bad">loaded ${esc(d.name)}, but these teams are NOT the ones it `
        +`saved</span> — ${esc(d.sha||'?')} then, ${esc(lastSha||'?')} now. Same knobs, `
        +`so the PBS data, the Smogon dump or the generator has moved since.`;
  };
  $('pset').onclick=async()=>{
    const r=await fetch('/api/preset',{method:'POST',body:JSON.stringify(
      {name:$('pname').value,overwrite:$('pow').checked,note:'',settings:get()})});
    const d=await r.json();
    if(d.error) return void($('pmsg').innerHTML='<span class="bad">'+esc(d.error)+'</span>');
    $('pmsg').innerHTML=`<span class="ok">wrote ${esc(d.ok)}</span> — fingerprint `
      +`${esc(d.sha)}, ${d.errors} validator errors. Commit it to share it.`;
    await presetList($('pname').value.replace(/\.json$/,''));
  };
  $('save').onclick=async()=>{
    const r=await fetch('/api/export',{method:'POST',body:JSON.stringify(
      {name:$('fname').value,overwrite:$('ow').checked,settings:get()})});
    const d=await r.json();
    $('msg').innerHTML=d.error?`<span class="bad">${d.error}</span>`
      :`<span class="ok">wrote ${d.ok} — ${d.errors} validator errors</span>`;};
  go();
}
init();
</script></body></html>"""

if __name__ == "__main__":
    port = PORT
    if "--port" in sys.argv:
        port = int(sys.argv[sys.argv.index("--port") + 1])
    TS.profile()
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"boss studio → http://127.0.0.1:{port}    (ctrl-c to stop)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
