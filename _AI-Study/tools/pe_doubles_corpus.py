#!/usr/bin/env python3
"""The corpus stage of the doubles differential: replay Showdown doubles turns on poke-engine.

Consumes generated/showdown_doubles_corpus.ndjson (tools/showdown_doubles_corpus.js) and for
every turn rebuilds the position as a poke-engine doubles State, using the stats Showdown
computed, runs the same joint action, and compares three roll-independent projections:

  bodies damaged  which bodies took damage at all -- targeting, spread, redirection, guards
  boosts          which bodies got which stat changes
"Which body acted" is NOT measured here, and cannot be: poke-engine emits DecrementPP only
when a move is below 10 PP (generate_instructions.rs:2488, an optimisation -- PP only matters
near exhaustion), and SetLastUsedMove does not appear for an ordinary move either. So the
instruction stream carries no general signal for which body executed which move, and the
slot-versus-body action binding found in the Ally Switch case has to be probed case by case
through damage magnitude instead. Recorded because it looks measurable and is not.

Absolute damage is deliberately not compared: poke-engine branches on the roll, and its most
probable branch is ~0.88 of Showdown's pinned max roll. The per-hit ratio is reported as a
number for reference, not as a verdict.

A turn whose position contains anything poke-engine cannot represent is SKIPPED and counted
by reason, never mistranslated. That skip rate is itself the literal answer to "coverage
against Showdown".

Requires the doubles bindings and patches/poke_engine_doubles_debug_slot.patch -- see
tools/pe_doubles_diff.py for both.

    python3 tools/pe_doubles_corpus.py [corpus.ndjson]
"""
import json, re, sys, collections, statistics
from poke_engine import State, Side, Pokemon, Move, SideConditions, generate_instructions

_VALUED = ("--without", "--only", "--dump")
_pos = [a for i, a in enumerate(sys.argv[1:], 1)
        if not a.startswith("--") and sys.argv[i - 1] not in _VALUED]
SRC = _pos[0] if _pos else "generated/showdown_doubles_corpus.ndjson"
# --without <tag> drops every turn carrying that tag, which is how a known bug is held out to
# see what disagreement is left behind it (see the Wide Guard hold-out in SEARCH-BOARDS.md).
EXCLUDE = {sys.argv[i + 1] for i, a in enumerate(sys.argv) if a == "--without"}
# --only <tag> is the inverse: keep ONLY turns carrying that tag. The headline percentages
# print six example disagreements in total, which is no help when the question is "what do
# the eleven turns with THIS mechanic actually do" -- the bucket gives a count and nothing
# to read. Repeatable, and unioned (a turn is kept if it carries any of the tags).
ONLY = {sys.argv[i + 1] for i, a in enumerate(sys.argv) if a == "--only"}
# --all-fails prints EVERY disagreeing turn instead of the first six, and marks which of the
# disagreeing bodies FAINTED during the turn. Added in run 8, because six examples cannot answer
# "how many of these rows are comparable at all": Showdown's clearVolatile() zeroes a fainted
# body's boosts and poke-engine does not (it clears them later, on the replacement switch), so a
# row whose only disagreement is a dead body's boosts is an instrument artefact. The STATUS
# projection has always had a fainted guard (`pe_doubles_diff.py:89`); the boosts one never did.
ALL_FAILS = "--all-fails" in sys.argv
# --dump <battle>:<turn> prints the engine's full top-branch instruction list for one row. Once
# the projections have narrowed the residual to a handful of named turns, the deltas alone stop
# being enough to name a defect -- "poke-engine only: spa +1" does not say WHICH of two boosts
# went missing -- and the instruction list does.
_dump = [sys.argv[i + 1] for i, a in enumerate(sys.argv) if a == "--dump"]
DUMP = tuple(int(x) for x in _dump[0].split(":")) if _dump else None
pid = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())

WEATHER = {"none": "none", "raindance": "rain", "sunnyday": "sun", "sandstorm": "sand", "hail": "hail"}
CONDITION = {"stealthrock": "stealth_rock", "spikes": "spikes", "toxicspikes": "toxic_spikes",
             "reflect": "reflect", "lightscreen": "light_screen", "tailwind": "tailwind",
             "safeguard": "safeguard", "mist": "mist", "luckychant": "lucky_chant",
             "wideguard": "wide_guard", "quickguard": "quick_guard", "stickyweb": "sticky_web"}
# Showdown's status codes are not poke-engine's names (its enum is NONE/BURN/SLEEP/FREEZE/
# PARALYZE/POISON/TOXIC), and an unmapped one panics the binding with "Invalid PokemonStatus".
# The synthetic pool inflicts no status, so only real teams reach this.
STATUS = {"": "none", "none": "none", "fnt": "none", "slp": "sleep", "par": "paralyze",
          "brn": "burn", "psn": "poison", "tox": "toxic", "frz": "freeze"}

VOLATILE = {"confusion": "confusion", "substitute": "substitute", "leechseed": "leechseed",
            "taunt": "taunt", "encore": "encore", "protect": None, "followme": None,
            "ragepowder": None, "endure": None, "allyswitch": None, "helpinghand": None,
            "wideguard": None, "quickguard": None,
            # Showdown's consecutive-protection counter. Not inert: its success check is
            # randomChance(1, counter), which under the pinned always-max PRNG makes a
            # REPEATED protection move fail. It is therefore ignored for representability
            # but the turn is skipped if a body carrying it actually chooses one of
            # STALL_MOVES -- the only situation in which it changes anything.
            "stall": None,
            # A Choice lock is not a volatile in poke-engine: it rides on Move.disabled (see
            # `mon`). Flash Fire and the Hyper Beam recharge DO exist there.
            "choicelock": None, "flashfire": "flashfire", "mustrecharge": "mustrecharge",

            # --- run 11: the three that used to be counted skips -------------------------
            # `disable` needs no mapping. poke-engine HAS a DISABLE volatile, but nothing
            # reads it to restrict a choice -- its only non-application use site is an Aroma
            # Veil gate (`genx/state.rs:780`), while `move_is_selectable` reads the per-move
            # `Move.disabled` flag, which run 9's whitelist already fills from Showdown's own
            # per-move `disabled`. So the EFFECT is modelled and the volatile is redundant.
            "disable": None,
            # `twoturnmove` likewise. Showdown's condition does `attacker.addVolatile(effect.id)`
            # in its own onStart (`data/conditions.ts:294`), so a charging body carries BOTH
            # `twoturnmove` and a volatile named after the move -- and it is the move-named one
            # that poke-engine reads, via `active_is_charging_move_slot`'s CHARGE_VOLATILES
            # table (`genx/state.rs:1134`). Mapping the generic marker to an engine name would
            # be wrong; mapping its siblings is the fix.
            "twoturnmove": None,
            # The siblings. Every one of these is both a Showdown volatile id and a
            # poke-engine PokemonVolatileStatus of the same name, and each appears in
            # CHARGE_VOLATILES, so passing it makes `slot_options_doubles` (`:1648`) return the
            # single charge option instead of a full move list -- which is what Showdown's
            # single-entry request says too. Gen 5 reaches the first twelve; the rest are
            # later-gen and cost nothing to map.
            **{v: v for v in ("solarbeam", "fly", "dig", "dive", "bounce", "skullbash",
                              "skyattack", "razorwind", "freezeshock", "iceburn",
                              "shadowforce", "skydrop", "phantomforce", "meteorbeam",
                              "electroshot", "geomancy", "solarblade")},
            # Outrage / Thrash / Petal Dance. Passed WITHOUT a duration, which is a recorded
            # approximation rather than a free win: the engine counts lockedmove UP (0, 1, then
            # at 2 it removes the volatile and applies confusion, `generate_instructions.rs:3898`)
            # while Showdown counts a hidden `trueDuration` DOWN from random(2,4), and the
            # snapshot carries no counter at all. A lock therefore always looks FRESH to the
            # search, so it over-estimates how long the body stays locked. Safe in the sense
            # that matters -- only a duration above 2 panics (the `_ =>` arm of the taunt-style
            # match), and 0 is the engine's own start value.
            "lockedmove": "lockedmove",

            # `slowstart` is deliberately NOT mapped, and this is a downgrade from the old
            # table, which claimed it. Passing it with the duration the snapshot cannot supply
            # is actively harmful: the end-of-turn block does `slowstart -= 1` and then tests
            # `== 0` (`generate_instructions.rs:3880`), so a duration of 0 goes to -1 and the
            # volatile is NEVER removed -- a permanently halved-Attack body in the search's
            # model. Inert is strictly better than wrong. Costs nothing here: Slow Start is
            # 0 bodies in all 183 gen5doublesou teams (Regigigas 0, and Truant/Unburden 0 too).
            "slowstart": None}

# Every move that feeds Showdown's `stall` counter, not just Protect. Wide Guard and Quick
# Guard both call `onHitSide -> source.addVolatile('stall')` (`data/moves.ts:20816` and
# `:14498`), and Detect/Endure do the same. Re-chosen by a body already carrying `stall`,
# any of them FAILS under the always-max PRNG, while poke-engine has no stall counter at all
# (defect 12) and succeeds -- so the turn cannot be compared soundly in either direction and
# is skipped, exactly as repeated Protect already was.
#
# This was a real flaw in this harness: the skip below used to test `id == "protect"` alone,
# so 71 turns in which a stalled body re-chose WIDE GUARD were compared anyway and counted
# against the engine. Gen 5 only, so no King's Shield / Spiky Shield / Baneful Bunker.
STALL_MOVES = {"protect", "detect", "endure", "wideguard", "quickguard"}

class Skip(Exception):
    pass

def mon(d, allow_fainted=False, usable=None):
    """Translate one body. By default a fainted active is a Skip, because the differential
    corpus wants positions both engines agree are well formed. The play harness passes
    allow_fainted=True: late in a battle a side with an empty bench keeps a fainted body on
    the field, and refusing those silently hands every such decision to the fallback policy.

    `usable`, when given, is the set of pid'd move ids Showdown will accept from this body this
    turn; every other move is built with `disabled=True`. poke-engine has no Choice-lock rule
    of its own -- `move_is_selectable` (`genx/state.rs:500`) reads `Move.disabled` and never
    looks at the held item, in the fork and upstream alike -- so filling this is the CALLER's
    job, exactly as `tools/foul_play_sidecar.py:173` does for singles. Pass None for a body
    whose legal set is unknown (a benched one, or a side with no pending request) and nothing
    is disabled, which is the engine's own default. See tools/pe_doubles_choicelock.py."""
    if d is None:
        raise Skip("empty active slot")
    if d.get("fainted"):
        if not allow_fainted:
            raise Skip("fainted or empty active slot")
        # Showdown marks a fainted body with status "fnt", which poke-engine has no
        # equivalent for -- hp 0 is how it represents the same thing, and passing "fnt"
        # through panics the binding with "Invalid PokemonStatus: FNT".
        d = dict(d, hp=0, status="none")
    for v in d["volatiles"]:
        if v not in VOLATILE:
            raise Skip(f"volatile {v}")
    t = [pid(x) for x in d["types"]]
    return Pokemon(
        id=pid(d["species"]), level=100,
        types=(t[0], t[1] if len(t) > 1 else "typeless"),
        hp=d["hp"], maxhp=d["maxhp"],
        attack=d["stats"]["atk"], defense=d["stats"]["def"],
        special_attack=d["stats"]["spa"], special_defense=d["stats"]["spd"],
        speed=d["stats"]["spe"],
        ability=pid(d["ability"]), item=pid(d["item"]) if d["item"] else "none",
        status=STATUS.get(pid(d["status"]), pid(d["status"])),
        weight_kg=float(d.get("weightkg") or 0),
        attack_boost=d["boosts"].get("atk", 0), defense_boost=d["boosts"].get("def", 0),
        special_attack_boost=d["boosts"].get("spa", 0), special_defense_boost=d["boosts"].get("spd", 0),
        speed_boost=d["boosts"].get("spe", 0), accuracy_boost=d["boosts"].get("accuracy", 0),
        evasion_boost=d["boosts"].get("evasion", 0),
        moves=[Move(id=pid(m["id"]), pp=m["pp"],
                    disabled=usable is not None and pid(m["id"]) not in usable)
               for m in d["moves"]],
        # last_used_move carries ENCORE and the Bloodmoon / Gigaton Hammer repeat ban, and
        # nothing else. It is serialized as "move:<index into this body's own move list>".
        #
        # It does NOT carry a Choice lock, and an earlier version of this comment claimed it
        # did. Defect 4 -- "doubles option generation does not enforce the Choice lock it is
        # given" -- was that claim's consequence: the lock rides on Move.disabled above, which
        # this translator never filled, so the engine was told nothing was disabled and
        # correctly offered everything.
        last_used_move=next((f"move:{i}" for i, m in enumerate(d["moves"])
                             if pid(m["id"]) == pid(d.get("lastMove") or "")), "move:none"),
        # The volatiles, ACTUALLY passed. Until run 11 this argument was absent entirely, so
        # the loop above only validated `d["volatiles"]` and then threw them away -- the
        # `VOLATILE` table implied a translation that never happened. Harmless for every
        # figure in SEARCH-BOARDS.md (0 of the 456 corpus turns carry a volatile on an active
        # OR a bench body, checked rather than assumed), but it silently cost the play harness
        # every charging and locked body, and it made run 10's first Encore probe inert.
        #
        # A None in the table means "representable as nothing" and is dropped here. Names are
        # still validated above rather than passed through, because `from_str` ends in
        # `_ => Ok(default)` (`src/lib.rs:65`): an unrecognised name does not error, it
        # silently becomes NONE and is inserted into the bitset.
        volatile_statuses={VOLATILE[v] for v in d["volatiles"] if VOLATILE[v]},
        # Durations are left at their zero defaults on purpose. The snapshot has no counters,
        # and for the three volatiles whose durations the engine reads (lockedmove, taunt,
        # encore) zero is the engine's own start value and lands in a safe match arm; slowstart
        # is the one where zero is NOT safe, which is why it is unmapped above.
        substitute_health=int(d.get("subHp") or 0),
    )

def build_side(s, allow_fainted=False, usable=None):
    """`usable[slot]`, when given, is the set of pid'd move ids Showdown accepts from that
    active slot (see `mon`). Bench bodies never take one -- Showdown reports legality for the
    field only, the same gate `foul_play_sidecar.py` spells as `on_field`."""
    kw = {}
    for k, v in s["conditions"].items():
        if k not in CONDITION:
            raise Skip(f"side condition {k}")
        kw[CONDITION[k]] = int(v)
    party = [mon(p, allow_fainted, usable=(usable or {}).get(i))
             for i, p in enumerate(s["active"])] \
        + [mon(p) for p in s["bench"] if not p.get("fainted")]
    return Side(active_indices=["0", "1"], pokemon=party,
                side_conditions=SideConditions(**kw) if kw else SideConditions())

def action(parts):
    out = []
    for p in parts:
        if p["kind"] == "pass":
            out.append("none")
        elif p["kind"] == "switch":
            out.append(pid(p["species"]))
        else:
            out.append(p["id"] + ("" if p["target"] is None else f",{p['target']}"))
    return ";".join(out)

DMG = re.compile(r"^Damage (SideOne|SideTwo):(\d+): (-?\d+)$")
BST = re.compile(r"^Boost (SideOne|SideTwo):(\d+) (\w+): (-?\d+)$")
SWI = re.compile(r"^Switch (SideOne|SideTwo): P(\d+) -> P(\d+)$")
SWP = re.compile(r"^SwapActiveSlots\((SideOne|SideTwo)\)$")
PPD = re.compile(r"^DecrementPP (SideOne|SideTwo):(\d+): M(\d+) \d+$")
STAT = {"Attack": "atk", "Defense": "def", "SpecialAttack": "spa", "SpecialDefense": "spd",
        "Speed": "spe", "Accuracy": "accuracy", "Evasion": "evasion"}

def pe_project(branch, names, roster, movelists):
    names = dict(names)
    dmg, boost, acted = collections.Counter(), collections.Counter(), set()
    for ins in branch.instruction_list:
        s = str(ins)
        m = SWI.match(s)
        if m:
            who = "s1" if m[1] == "SideOne" else "s2"
            leaving = roster[(who, int(m[2]))]
            slot = next((sl for (w, sl), n in names.items() if w == who and n == leaving), 0)
            names[(who, slot)] = roster[(who, int(m[3]))]
            continue
        if SWP.match(s):
            who = "s1" if SWP.match(s)[1] == "SideOne" else "s2"
            names[(who, 0)], names[(who, 1)] = names[(who, 1)], names[(who, 0)]
            continue
        m = PPD.match(s)
        if m:
            who = "s1" if m[1] == "SideOne" else "s2"
            body = names[(who, int(m[2]))]
            mv = movelists.get((who, body), [])
            acted.add((who, body, mv[int(m[3])] if int(m[3]) < len(mv) else f"M{m[3]}"))
            continue
        m = DMG.match(s)
        if m:
            who = "s1" if m[1] == "SideOne" else "s2"
            dmg[(who, names[(who, int(m[2]))])] += int(m[3]); continue
        m = BST.match(s)
        if m:
            who = "s1" if m[1] == "SideOne" else "s2"
            boost[(who, names[(who, int(m[2]))], STAT.get(m[3], m[3]))] += int(m[4])
    return dmg, boost, acted

MOVELINE = re.compile(r"^\|move\|(p[12])([ab]): ([^|]+)\|([^|]+)\|")

def sd_project(row):
    dmg, boost = collections.Counter(), collections.Counter()
    for b, a in zip(row["before"]["sides"], row["after"]["sides"]):
        who = "s1" if b["side"] == "p1" else "s2"
        was = {p["species"]: p for p in b["active"] + b["bench"] if p}
        for p in [x for x in a["active"] + a["bench"] if x]:
            pb = was.get(p["species"])
            if not pb:
                continue
            if pb["hp"] - p["hp"]:
                dmg[(who, p["species"])] = pb["hp"] - p["hp"]
            for stat, v in p["boosts"].items():
                if v - pb["boosts"].get(stat, 0):
                    boost[(who, p["species"], stat)] = v - pb["boosts"].get(stat, 0)
    acted = set()
    for line in row["log"]:
        m = MOVELINE.match(line)
        if m:
            acted.add(("s1" if m[1] == "p1" else "s2", m[3].split(",")[0].strip(), pid(m[4])))
    return dmg, boost, acted

# ---- run --------------------------------------------------------------------------------

def tags(row, s1, s2):
    """What is in play this turn, so a disagreement can be attributed to a mechanic rather
    than left as a bare percentage."""
    t = set()
    SPREAD = {"surf", "earthquake", "swift"}
    GUARD = {"wideguard", "quickguard"}
    for who, parts, sd in (("s1", row["parts"]["s1"], s1), ("s2", row["parts"]["s2"], s2)):
        for slot, part in enumerate(parts or []):
            if part["kind"] == "switch":
                t.add("switch from slot 1" if slot == 1 else "switch from slot 0")
            elif part["kind"] == "move":
                if part["id"] in SPREAD: t.add("spread move")
                if part["id"] in GUARD: t.add(part["id"])
                if part["id"] in {"followme", "ragepowder"}: t.add("redirection move")
                if part["id"] == "allyswitch": t.add("allyswitch")
                if part["id"] == "helpinghand": t.add("helpinghand")
                if part["id"] == "protect": t.add("protect")
        for p in sd["active"]:
            if p and pid(p["ability"]) in {"lightningrod", "stormdrain", "friendguard", "telepathy", "intimidate"}:
                t.add("ability " + pid(p["ability"]))
            if p and any(v for v in p["boosts"].values()):
                t.add("a body carries boosts")
    return t

tally = collections.Counter()
buckets = {"bodies damaged": collections.Counter(), "boosts": collections.Counter()}
seen_tags = collections.Counter()
skips = collections.Counter()
fails = collections.defaultdict(list)
ratios = []
for line in open(SRC, encoding="utf8"):
    row = json.loads(line)
    tally["turns"] += 1
    try:
        s1, s2 = row["before"]["sides"]
        if row["before"]["weather"] not in WEATHER:
            raise Skip(f"weather {row['before']['weather']}")
        if row["before"]["terrain"] != "none":
            raise Skip(f"terrain {row['before']['terrain']}")
        for ps in row["before"]["pseudo"]:
            if ps != "trickroom":
                raise Skip(f"pseudo weather {ps}")
        state = State(side_one=build_side(s1), side_two=build_side(s2),
                      weather=WEATHER[row["before"]["weather"]],
                      trick_room="trickroom" in row["before"]["pseudo"])
        stalled = {p["species"] for s in (s1, s2) for p in s["active"] if p and "stall" in p["volatiles"]}
        for who, parts in (("s1", row["parts"]["s1"]), ("s2", row["parts"]["s2"])):
            side_d = s1 if who == "s1" else s2
            for slot, part in enumerate(parts or []):
                if part["kind"] == "move" and part["id"] in STALL_MOVES \
                   and side_d["active"][slot] and side_d["active"][slot]["species"] in stalled:
                    raise Skip(f"repeated {part['id']} under Showdown's stall counter")
    except Skip as exc:
        skips[str(exc)] += 1; continue
    except Exception as exc:
        skips[f"state build failed: {type(exc).__name__} {exc}"] += 1; continue

    names, roster, movelists = {}, {}, {}
    for who, s in (("s1", s1), ("s2", s2)):
        party = [p for p in s["active"] if p] + [p for p in s["bench"] if p and not p.get("fainted")]
        for idx, p in enumerate(party):
            roster[(who, idx)] = p["species"]
            movelists[(who, p["species"])] = [pid(m["id"]) for m in p["moves"]]
        for slot, p in enumerate(s["active"]):
            names[(who, slot)] = p["species"]
    try:
        branches = generate_instructions(state, action(row["parts"]["s1"]), action(row["parts"]["s2"]))
    except Exception as exc:
        skips[f"action rejected: {exc}"] += 1; continue
    tally["compared"] += 1
    top = max(branches, key=lambda b: b.percentage)
    if DUMP == (row["battle"], row["turn"]):
        print(f"--- dump battle {row['battle']} turn {row['turn']}  {row['choices']}")
        print(f"    top branch {top.percentage:.1f}%  ({len(branches)} branches)")
        for ins in top.instruction_list:
            print("   ", ins)
    pe_d, pe_b, pe_a = pe_project(top, names, roster, movelists)
    sd_d, sd_b, sd_a = sd_project(row)

    # Boosts are compared only for bodies that are active in both snapshots: a body that
    # switched out has its boosts cleared, and that reset would otherwise read as a
    # disagreement about a body nobody touched.
    on_field = {(w, p["species"]) for w, s in (("s1", s1), ("s2", s2)) for p in s["active"] if p}
    on_field &= {("s1" if s["side"] == "p1" else "s2", p["species"])
                 for s in row["after"]["sides"] for p in s["active"] if p}
    sd_b = {k: v for k, v in sd_b.items() if (k[0], k[1]) in on_field}
    pe_b = {k: v for k, v in pe_b.items() if (k[0], k[1]) in on_field}

    # A body that FAINTED this turn is not comparable on boosts, and this guard is boosts-only.
    # Showdown zeroes a fainted body's boosts inside faintMessages (`sim/battle.ts:2563` calls
    # `clearVolatile(false)`, which resets `boosts` outright); poke-engine keeps them until the
    # replacement switch clears them, and `evaluate.rs` never reads them, since every boost read
    # sits behind `pkmn.hp > 0` (`:165`, `:198`). So the divergence is real but inert — and
    # comparing it charged the engine for 12 of the 14 boosts rows still disagreeing after run 7.
    # Deliberately NOT applied to bodies-damaged: a body that fainted genuinely *did* take
    # damage, so excluding it there would hide real disagreements (corpus battle 5 turn 10 is
    # exactly that shape). The STATUS projection has always had this guard
    # (`pe_doubles_diff.py:89`); the boosts one never did.
    dead_bodies = {(("s1" if s["side"] == "p1" else "s2"), p["species"])
                   for s in row["after"]["sides"] for p in s["active"]
                   if p and p["hp"] == 0}
    sd_b = {k: v for k, v in sd_b.items() if (k[0], k[1]) not in dead_bodies}
    pe_b = {k: v for k, v in pe_b.items() if (k[0], k[1]) not in dead_bodies}
    row_tags = tags(row, s1, s2)
    if row_tags & EXCLUDE:
        skips[f"held out by --without {sorted(row_tags & EXCLUDE)}"] += 1
        tally["compared"] -= 1
        continue
    if ONLY and not (row_tags & ONLY):
        skips[f"not selected by --only {sorted(ONLY)}"] += 1
        tally["compared"] -= 1
        continue
    for t in row_tags:
        seen_tags[t] += 1
    for label, sd, pe in (("bodies damaged", set(sd_d), set(pe_d)),
                          ("boosts", set(sd_b.items()), set(pe_b.items()))):
        if sd == pe:
            tally[label + " agree"] += 1
        else:
            tally[label + " differ"] += 1
            for t in row_tags:
                buckets[label][t] += 1
            if ALL_FAILS or len(fails[label]) < 6:
                dead = {(("s1" if s["side"] == "p1" else "s2"), p["species"])
                        for s in row["after"]["sides"] for p in s["active"]
                        if p and p["hp"] == 0}
                fails[label].append((row["battle"], row["turn"], row["choices"],
                                     sorted(sd - pe), sorted(pe - sd), dead))
    for k in set(sd_d) & set(pe_d):
        if sd_d[k]:
            ratios.append(pe_d[k] / sd_d[k])

print(f"turns in corpus     : {tally['turns']}")
print(f"compared            : {tally['compared']}")
print(f"skipped (not compared, by reason):")
for reason, n in skips.most_common():
    print(f"    {n:5}  {reason}")
print()
for label in ("bodies damaged", "boosts"):
    a, d = tally[label + " agree"], tally[label + " differ"]
    if a + d:
        print(f"{label:16}: {a}/{a+d} agree  ({100*a/(a+d):.1f}%)")
if ratios:
    print(f"\ndamage ratio pe(top branch)/showdown(max roll): median {statistics.median(ratios):.3f} "
          f"over {len(ratios)} hits  (roll model, not mechanics)")
for label in ("bodies damaged", "boosts"):
    d = tally[label + " differ"]
    if not d:
        continue
    print(f"\ndisagreeing turns by what was in play ({label}, {d} turns; a turn can carry several):")
    for t, n in buckets[label].most_common(10):
        base = seen_tags[t]
        print(f"    {n:4}/{base:<4} ({100*n/base:5.1f}% of turns with it)  {t}")
# The two projections do NOT carry the same shape, which is the trap here: bodies-damaged
# entries are plain keys `(who, species)`, while boosts entries are PAIRS
# `((who, species, stat), amount)` because they come from `dict.items()`. Taking `k[:2]` for both
# reported "0 of 14" fainted-only boosts rows when the true answer is most of them — the bodies
# rows tagged correctly the whole time, and only reading the snapshots by hand first exposed it.
def body_of(k):
    return k[0][:2] if isinstance(k[0], tuple) else k[:2]

for label, rows_ in fails.items():
    print(f"\n--- {'all' if ALL_FAILS else 'first'} disagreements: {label}")
    n_dead = 0
    for battle, turn, choices, only_sd, only_pe, dead in rows_:
        bodies = {body_of(k) for k in only_sd} | {body_of(k) for k in only_pe}
        tag = ""
        if bodies and bodies <= dead:
            tag = "   [EVERY disagreeing body FAINTED this turn -- not comparable]"
            n_dead += 1
        elif bodies & dead:
            tag = f"   [fainted this turn: {sorted(bodies & dead)}]"
        print(f"  battle {battle} turn {turn}  p1={choices['p1']!r} p2={choices['p2']!r}{tag}")
        if only_sd: print(f"    showdown only : {only_sd}")
        if only_pe: print(f"    poke-engine only: {only_pe}")
    if ALL_FAILS:
        print(f"  => {n_dead} of {len(rows_)} {label} rows disagree ONLY about bodies that "
              f"fainted this turn")
