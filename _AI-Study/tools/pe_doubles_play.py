#!/usr/bin/env python3
"""Play doubles with poke-engine's search as the policy and Showdown as the referee.

The point of this harness is the separation: **Showdown adjudicates every turn, poke-engine
only plans**. The board is therefore correct by construction, so a loss is the planner's
fault and not the board's -- which is exactly what could not be said of the Ruby projection.
No game, no adapter, no sidecar: this measures whether a doubles search is worth building a
bridge for, before the bridge exists.

    python3 tools/pe_doubles_play.py --battles 20 --p1 mcts --p2 greedy [--ms 300] [--seed 7]
                                     [--save-log DIR]

--save-log writes one readable transcript per battle: each side's chosen actions, the search's
own root ranking with visit counts (its reasoning, so a loss can be read rather than guessed
at), the moves Showdown actually resolved, and the HP that resulted. Without it this harness
reports a score and nothing inspectable.

Policies:
  mcts    poke-engine `monte_carlo_tree_search` on the translated position; the most-visited
          root action is taken. Needs the doubles bindings and
          patches/poke_engine_doubles_choice_labels.patch, without which the chosen action
          cannot be read back at all (the label drops its target slot, and slot 1 is named
          with slot 0's moveset).
  greedy  highest-base-power damaging move at the foe with the lowest HP fraction; a status
          move only when nothing damaging is available. Computed from the dex data the server
          reports, so it shares no code with the engine under test.
  random  uniform over legal actions.

A position poke-engine cannot represent makes the mcts policy fall back to greedy for that
turn, counted and reported: a silent fallback would flatter the search.
"""
import argparse, collections, json, random, re, subprocess, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from poke_engine import State, Side, Pokemon, Move, SideConditions, monte_carlo_tree_search

# Species names for the log header, read from the shared pool the server draws teams from.
# Matches the species/ability/moves triple only -- a bare \['Name', also matches the move
# lists nested inside it.
POOL_NAMES = re.findall(r"\['([A-Za-z]+)',\s*'[A-Za-z ]+',\s*\[",
                        Path(__file__).with_name("showdown_doubles_lib.js").read_text())

EV_LABEL = {"hp": "HP", "atk": "Atk", "def": "Def", "spa": "SpA", "spd": "SpD", "spe": "Spe"}
DUMP = Path(__file__).parent.parent / "extracted" / "smogon-dump"


def set_text(m):
    """One scraped set as Showdown import text.

    The dump stores a mega as its mega species (`Gardevoir-Mega` holding `Gardevoirite`), and
    that is kept verbatim: the body simply starts mega. Stripping the forme instead would need
    mega choice syntax that neither policy here issues, so no mon would ever transform. The
    deviation is symmetric between sides; it is recorded in SEARCH-BOARDS.md.
    """
    out = [f"{m['species']} @ {m['item']}" if m.get("item") else m["species"]]
    if m.get("ability"):
        out.append(f"Ability: {m['ability']}")
    out.append("Level: 100")
    if m.get("evs"):
        out.append("EVs: " + " / ".join(f"{v} {EV_LABEL[k]}" for k, v in m["evs"].items() if v))
    if m.get("nature"):
        out.append(f"{m['nature']} Nature")
    if m.get("ivs"):
        out.append("IVs: " + " / ".join(f"{v} {EV_LABEL[k]}" for k, v in m["ivs"].items()))
    out += [f"- {mv}" for mv in m["moves"]]
    return "\n".join(out)


def load_dump_teams(tier, sizes=(6,), require=()):
    """Teams of the given sizes from extracted/smogon-dump, as Showdown import text.

    Six is the default, but gen 5 doubles on Smogon is largely **2v2 with four-mon teams**
    (gen5doublesou holds 158 of those against 13 complete sixes), and a four-mon team is a
    legal custom-game bring: team preview's `team 1234` puts two out and benches two.

    `require` keeps only teams carrying one of the named moves AND rotates the carrier to the
    front so it LEADS. Both halves are needed to test a mechanic: 25 of 171 gen 5 doubles teams
    carry Tailwind, but on a four-mon team the carrier is usually third or fourth, so it starts
    benched and arrives after the game is decided -- which is exactly why Tailwind was never
    used once across fifteen battles. Rotating the lead is a deviation from the authored team
    and is applied symmetrically to both sides; it is recorded in SEARCH-BOARDS.md."""
    raw = json.loads((DUMP / f"{tier}.json").read_text(encoding="utf8"))
    teams = [t for t in raw if len(t.get("data") or []) in sizes]
    if require:
        want = {pid(m) for m in require}
        kept = []
        for t in teams:
            i = next((k for k, m in enumerate(t["data"])
                      if want & {pid(x) for x in (m.get("moves") or [])}), None)
            if i is None:
                continue
            d = t["data"]
            t = dict(t, data=[d[i]] + d[:i] + d[i + 1:])   # carrier leads
            kept.append(t)
        teams = kept
    # The label carries the roster, not just the scraper's team name: a transcript whose header
    # reads "For london bw 2v2 classic" says nothing about who is playing.
    return [("\n\n".join(set_text(m) for m in t["data"]),
             "%s: %s" % (t.get("name") or "?", ", ".join(m["species"] for m in t["data"])),
             len(t["data"]))
            for t in teams]


CORPUS = Path(__file__).with_name("pe_doubles_corpus.py")
_ns = {}
exec(compile(CORPUS.read_text().split("# ---- run")[0], str(CORPUS), "exec"), _ns)
build_side, mon, Skip, WEATHER, pid = _ns["build_side"], _ns["mon"], _ns["Skip"], _ns["WEATHER"], _ns["pid"]


# Set from --dump-panics. An engine panic is raised INSIDE the search, so no transcript can show
# which hypothetical line reached it -- only the root position is recoverable. Dumping it is what
# lets a probe be built from evidence rather than from a guess.
PANIC_DUMP = None


class Server:
    """The Showdown referee, one battle at a time over the JSON-line protocol."""

    def __init__(self):
        self.p = subprocess.Popen(
            ["node", str(Path(__file__).with_name("showdown_doubles_server.js"))],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)

    def send(self, obj):
        self.p.stdin.write(json.dumps(obj) + "\n")
        self.p.stdin.flush()
        line = self.p.stdout.readline()
        if not line:
            raise RuntimeError("showdown server died")
        return json.loads(line)

    def close(self):
        try:
            self.send({"cmd": "quit"})
        except Exception:
            pass
        self.p.kill()


def slot_whitelists(req, side_snapshot, stats=None):
    """{slot: set of pid'd move ids Showdown will accept} for one side's active slots.

    Two request shapes must both be honoured, and mapping by id rather than by index covers
    them with a single rule -- anything absent from the request is unusable:

      * a Choice-locked (or Taunted, Assault Vested, Disabled) body lists all of its moves,
        with `disabled` set on the ones it may not pick;
      * a body inside a LOCKED move -- Outrage, a charging Solar Beam, a Hyper Beam recharge --
        gets a single-entry list instead, the other three absent entirely
        (`showdown_doubles_server.js`).
    """
    out = {}
    for slot, a in enumerate(req.get("active") or []):
        ok = {pid(m["id"]) for m in a["moves"] if not m["disabled"]}
        actives = side_snapshot["active"]
        body = actives[slot] if slot < len(actives) else None
        known = {pid(m["id"]) for m in (body or {}).get("moves", [])}
        if ok and known and not (ok & known):
            # The request and the snapshot disagree about this body's move ids. Disabling every
            # move on a naming mismatch would be a worse bug than the one being fixed, so leave
            # the slot unconstrained and make the disagreement visible instead of silent.
            if stats is not None:
                stats["whitelist: request and snapshot move ids disjoint"] += 1
            continue
        if not ok and stats is not None:
            stats["whitelist: every move disabled (Struggle territory)"] += 1
        out[slot] = ok
    return out


def to_state(position, reqs=None, stats=None):
    """Translate a Showdown position into a poke-engine doubles State, or raise Skip.

    `reqs` is the server's per-side request map from the SAME reply as `position`, so the two
    are one consistent snapshot. It is what carries move legality: without it every move
    reaches the engine as enabled and the search proposes Choice-locked moves (defect 4).
    Both sides are passed, not just the acting one -- the tree models the foe too, and a foe
    whose lock is ignored is a foe with three extra options it does not have."""
    s1, s2 = position["sides"]
    if position["weather"] not in WEATHER:
        raise Skip(f"weather {position['weather']}")
    if position["terrain"] != "none":
        raise Skip(f"terrain {position['terrain']}")
    for ps in position["pseudo"]:
        if ps != "trickroom":
            raise Skip(f"pseudo {ps}")
    white = {s["side"]: slot_whitelists((reqs or {}).get(s["side"]) or {}, s, stats)
             for s in position["sides"]}
    return State(side_one=build_side(s1, allow_fainted=True, usable=white[s1["side"]]),
                 side_two=build_side(s2, allow_fainted=True, usable=white[s2["side"]]),
                 weather=WEATHER[position["weather"]],
                 trick_room="trickroom" in position["pseudo"])


NEEDS_TARGET = {"normal", "any", "adjacentFoe"}
# Showdown requires an explicit ally index for these, given as a NEGATIVE slot number, and
# rejects the choice outright without it ("Can't move: Helping Hand needs a target").
ALLY_TARGET = {"adjacentAlly", "adjacentAllyOrSelf"}


def ally_alive(position, side, slot):
    actives = next(s for s in position["sides"] if s["side"] == side)["active"]
    other = actives[1 - slot] if len(actives) > 1 else None
    return bool(other and not other.get("fainted"))


def usable(moves, position, side, slot):
    """Legal moves minus ally-targeting ones with no living ally to aim at."""
    ok = [m for m in moves if not m["disabled"]]
    if not ally_alive(position, side, slot):
        ok = [m for m in ok if m["target"] not in ALLY_TARGET]
    return ok


def showdown_choice(req, parts):
    """Render per-slot decisions as one Showdown choice string."""
    out = []
    for slot, part in enumerate(parts):
        if part is None:
            # `pass` is legal only for a slot that CANNOT act. A body that must recharge --
            # or is mid-charge -- has exactly one move in its request, flagged `locked`, and
            # Showdown rejects the whole choice unless that move is named ("Can't pass: You
            # must make a choice"). poke-engine expresses both of those as MoveChoice::None
            # (`genx/state.rs:1642` for MUSTRECHARGE, `:1648` for a charge), so the None has
            # to be translated back rather than taken literally.
            #
            # Latent before run 11 rather than introduced by it: the whitelist alone already
            # disables every real move on a recharge turn, so the engine already returned
            # None there. It had simply never fired -- recharge moves are 2 of 183 teams --
            # and the failure mode is an ABORTED run, not a counted fallback, which is why
            # it is worth three lines to close.
            a = (req.get("active") or [None] * (slot + 1))[slot]
            locked = [m for m in (a or {}).get("moves", []) if m.get("locked")]
            if a and not a.get("fainted") and len(locked) == 1:
                out.append(f"move {locked[0]['n']}"); continue
            out.append("pass"); continue
        kind, value, target = part
        if kind == "switch":
            out.append(f"switch {value}")
        else:
            mv = next(m for m in req["active"][slot]["moves"] if m["id"] == value)
            if mv["target"] in ALLY_TARGET:
                out.append(f"move {mv['n']} -{2 if slot == 0 else 1}")
            elif mv["target"] in NEEDS_TARGET and target is not None:
                out.append(f"move {mv['n']} {target + 1}")
            else:
                out.append(f"move {mv['n']}")
    return ", ".join(out)


def policy_random(req, position, side, rng):
    parts = []
    used = set()
    for slot, a in enumerate(req["active"]):
        if a["fainted"] or a["species"] is None:
            parts.append(None); continue
        legal = usable(a["moves"], position, side, slot)
        bench = [b for b in req["bench"] if b["slot"] not in used]
        if bench and not (a["trapped"] or a.get("maybeTrapped")) and rng.random() < 0.2:
            b = bench[0]; used.add(b["slot"])
            parts.append(("switch", b["slot"], None)); continue
        m = rng.choice(legal) if legal else a["moves"][0]
        parts.append(("move", m["id"], rng.randrange(2) if m["target"] in NEEDS_TARGET else None))
    return parts


def policy_greedy(req, position, side, rng):
    foes = next(s for s in position["sides"] if s["side"] != side)["active"]
    order = sorted((i for i, p in enumerate(foes) if p and not p["fainted"]),
                   key=lambda i: foes[i]["hp"] / foes[i]["maxhp"])
    target = order[0] if order else 0
    parts = []
    for slot, a in enumerate(req["active"]):
        if a["fainted"] or a["species"] is None:
            parts.append(None); continue
        legal = usable(a["moves"], position, side, slot)
        dmg = [m for m in legal if m["basePower"] > 0]
        m = max(dmg, key=lambda m: m["basePower"]) if dmg else (legal[0] if legal else a["moves"][0])
        parts.append(("move", m["id"], target if m["target"] in NEEDS_TARGET else None))
    return parts


LABEL = re.compile(r"^(?:switch (?P<sw>[a-z0-9]+)|(?P<mv>[a-z0-9]+)(?:,(?P<t>\d+))?)$")


def policy_mcts(req, position, side, rng, ms, stats, note=None, reqs=None):
    try:
        state = to_state(position, reqs, stats)
    except Skip as exc:
        stats[f"fallback: {exc}"] += 1
        if note is not None:
            note.append(f"      search skipped ({exc}); greedy took the turn")
        return policy_greedy(req, position, side, rng)
    except Exception as exc:
        stats[f"fallback: state build {type(exc).__name__}"] += 1
        if note is not None:
            note.append(f"      position could not be built ({type(exc).__name__}); greedy took the turn")
        return policy_greedy(req, position, side, rng)
    try:
        result = monte_carlo_tree_search(state, duration_ms=ms)
    except BaseException as exc:
        # PanicException subclasses BaseException, so a plain `except Exception` lets an engine
        # panic kill the run. Real gen 6 positions do panic it ("Invalid boost value: -11"
        # inside the search), so the turn falls to greedy and the panic is counted rather than
        # silently absorbed.
        stats[f"engine panic: {str(exc).splitlines()[0][:60]}"] += 1
        if PANIC_DUMP is not None:
            d = Path(PANIC_DUMP)
            d.mkdir(parents=True, exist_ok=True)
            (d / f"{len(list(d.glob('*.json'))):03d}_{side}.json").write_text(json.dumps(
                {"panic": str(exc).splitlines()[0], "side": side,
                 "position": position, "request": req}, indent=1))
        if note is not None:
            note.append(f"      search PANICKED ({str(exc).splitlines()[0][:60]}); greedy took the turn")
        return policy_greedy(req, position, side, rng)
    options = result.side_one if side == "p1" else result.side_two
    if not options:
        stats["fallback: no root options"] += 1
        if note is not None:
            note.append("      search returned no root options; greedy took the turn")
        return policy_greedy(req, position, side, rng)
    best = max(options, key=lambda o: o.visits)
    if note is not None:
        top = sorted(options, key=lambda o: -o.visits)[:4]
        note.append(f"      search ({result.total_visits} visits): "
                    + " | ".join(f"{o.move_choice} {o.visits}v {o.total_score:.0f}" for o in top))
    stats["mcts decisions"] += 1
    stats["visits"] += result.total_visits
    parts = []
    for slot, sub in enumerate(best.move_choice.split(";")):
        sub = sub.strip().lower()   # MoveChoice::None renders as "No Move"
        if sub in ("none", "no move"):
            parts.append(None); continue
        m = LABEL.match(sub)
        if not m:
            stats[f"unparsed label {sub!r}"] += 1
            if note is not None:
                note.append(f"      search chose {sub!r}, which could not be parsed; greedy took the turn")
            return policy_greedy(req, position, side, rng)
        if m.group("sw"):
            b = next((b for b in req["bench"] if pid(b["species"]) == m.group("sw")), None)
            if b is None:
                stats["fallback: switch target not on bench"] += 1
                if note is not None:
                    note.append(f"      search chose to switch to {m.group('sw')}, which is not on the bench;"
                                " greedy took the turn")
                return policy_greedy(req, position, side, rng)
            parts.append(("switch", b["slot"], None))
        else:
            have = req["active"][slot]["moves"]
            ok = usable(have, position, side, slot)
            if not any(x["id"] == m.group("mv") for x in ok):
                # Distinguish the two very different causes: a move the body does not know
                # (the engine enumerated from the wrong slot) versus one Showdown has
                # DISABLED, which for a Choice-locked body means the search ignored the lock.
                known = next((x for x in have if x["id"] == m.group("mv")), None)
                why = ("disabled by Showdown (Choice lock or Taunt) but proposed anyway"
                       if known else "not in this body's move list at all")
                stats[f"fallback: {m.group('mv')} in slot {slot} {why}"] += 1
                if note is not None:
                    note.append(f"      ILLEGAL: search chose {m.group('mv')} for slot {slot}, {why}."
                                " Greedy took the turn -- this turn is NOT the search's")
                return policy_greedy(req, position, side, rng)
            parts.append(("move", m.group("mv"), int(m.group("t")) if m.group("t") else None))
    return parts


SWITCH_LINE = re.compile(r"^\|switch\|(p[12][ab]): [^|]+\|([^,|]+)[^|]*\|(\d+)/(\d+)")
MOVE_LINE = re.compile(r"^\|move\|(p[12][ab]): ([^|]+)\|([^|]+)\|([^|]*)\|?(.*)$")
FAINT_LINE = re.compile(r"^\|faint\|(p[12][ab]): (.+)$")
SWAP_LINE = re.compile(r"^\|swap\|(p[12][ab]): ([^|]+)\|(\d+)")
# Outcome lines: whether the action above actually did anything.
OUTCOME_LINE = re.compile(r"^\|(-status|-curestatus|-fail|-immune|-miss|-crit|-boost|-unboost"
                          r"|-activate|cant|-start|-end|-enditem)\|([^|]*)\|?(.*)$")


def readable(line):
    """Showdown protocol as a sentence. Its raw form duplicates the species and reads as if
    the arriving Pokemon were the actor (`|switch|p1a: Blastoise|Blastoise, F|299/299`), which
    makes a switch look like a failed attempt by the body that arrived."""
    m = SWITCH_LINE.match(line)
    if m:
        return f"{m[1]} <- {m[2]} comes in ({m[3]}/{m[4]})"
    m = MOVE_LINE.match(line)
    if m:
        extra = f"  [{m[5].strip('|')}]" if m[5].strip('|') else ""
        target = f" -> {m[4]}" if m[4] and m[4] != f"{m[1]}: {m[2]}" else ""
        return f"{m[1]} {m[2]} used {m[3]}{target}{extra}"
    m = FAINT_LINE.match(line)
    if m:
        return f"{m[1]} {m[2]} fainted"
    m = SWAP_LINE.match(line)
    if m:
        return f"{m[1]} {m[2]} swapped to slot {m[3]}"
    m = OUTCOME_LINE.match(line)
    if m:
        who = m[2].replace(": ", " ")   # keep the p1a/p2b prefix: mirror matches are common
        phrase = {"-status": "is now {}", "-curestatus": "is cured of {}",
                  "-fail": "-- IT FAILED", "-immune": "-- IMMUNE", "-miss": "-- MISSED",
                  "-crit": "-- critical hit", "-boost": "{} rose", "-unboost": "{} fell",
                  "-activate": "-- {}", "cant": "COULD NOT MOVE ({})",
                  "-start": "gained {}", "-end": "lost {}", "-enditem": "used up its {}"}
        arg = " ".join(x for x in m[3].strip("|").split("|") if x and not x.startswith("["))
        body = phrase.get(m[1], m[1] + " {}")
        return f"        {who} " + (body.format(arg) if "{}" in body else body)
    return line.strip("|").replace("|", " ")


def forced_choice(req, rng):
    o = [b["slot"] for b in req["bench"]]
    return ", ".join(f"switch {o.pop(0)}" if f and o else "pass" for f in req["forceSwitch"])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--battles", type=int, default=20)
    ap.add_argument("--p1", default="mcts", choices=["mcts", "greedy", "random"])
    ap.add_argument("--p2", default="greedy", choices=["mcts", "greedy", "random"])
    ap.add_argument("--ms", type=int, default=300, help="MCTS budget per decision")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--max-turns", type=int, default=60)
    ap.add_argument("--save-log", metavar="DIR", help="write one transcript per battle here")
    ap.add_argument("--dump-panics", metavar="DIR",
                    help="write the root position (and its request) to DIR whenever the search "
                         "panics, so the state can be replayed in a probe")
    ap.add_argument("--teams", default="pool",
                    help="'pool' for the synthetic mechanic pool, or a smogon-dump tier such "
                         "as gen6doublesou (real scraped teams, complete six-mon only)")
    ap.add_argument("--team-sizes", default="6",
                    help="comma-list of team sizes to accept from the dump, e.g. 4,6")
    ap.add_argument("--require-move", default=None, metavar="MOVES",
                    help="comma-list; keep only dump teams carrying one of these moves, and "
                         "start the carrier rather than benching it (e.g. Tailwind,Trick Room)")
    ap.add_argument("--format", dest="fmt", default=None,
                    help="Showdown format id; defaults to match --teams")
    args = ap.parse_args()
    global PANIC_DUMP
    PANIC_DUMP = args.dump_panics

    require = tuple(x.strip() for x in args.require_move.split(",")) if args.require_move else ()
    dump = None if args.teams == "pool" else load_dump_teams(
        args.teams, tuple(int(x) for x in args.team_sizes.split(",")), require)
    fmt = args.fmt or ("gen5doublescustomgame" if args.teams == "pool"
                       else args.teams.split("doubles")[0] + "doublescustomgame")
    by_size = collections.defaultdict(list)
    for k, row in enumerate(dump or []):
        by_size[row[2]].append(k)
    if dump is not None and not any(len(v) >= 2 for v in by_size.values()):
        sys.exit(f"{args.teams} has no team size with two or more teams at sizes "
                 f"{args.team_sizes}; sizes found: {dict((k, len(v)) for k, v in by_size.items())}")
    if dump is not None:
        print("   teams: " + ", ".join(f"{len(v)} of size {k}" for k, v in sorted(by_size.items()))
              + "   (paired only against equal size)"
              + (f"   requiring {'/'.join(require)}, carrier leads" if require else ""))
    server = Server()
    stats = collections.Counter()
    wins = collections.Counter()
    try:
        for battle in range(args.battles):
            rng = random.Random(args.seed * 1000 + battle)
            if dump is None:
                pool = list(range(14))
                rng.shuffle(pool)
                teams = [pool[:4], pool[4:8]]
                names = [[POOL_NAMES[i] for i in t] for t in teams]
                req = {"cmd": "new", "teams": teams}
            else:
                # Pair only teams of the SAME size. --team-sizes says which sizes are
                # acceptable, not that they may fight each other: the format is a custom game
                # with no bring-N team preview, so a six-mon team fields all six and a 4-v-6
                # is a two-Pokemon handicap decided before a move is chosen.
                i = rng.randrange(len(dump))
                same = by_size[dump[i][2]]
                j = i
                while j == i:
                    j = same[rng.randrange(len(same))]
                names = [[dump[i][1]], [dump[j][1]]]
                # Real sets carry sub-100% moves, crits and secondaries, so the always-max PRNG
                # is wrong here: it would make every Hurricane miss. Showdown's own seeded PRNG
                # keeps a run reproducible while letting the search plan under real uncertainty,
                # which is what it does natively.
                req = {"cmd": "new", "p1": dump[i][0], "p2": dump[j][0], "format": fmt,
                       "pinPrng": False, "seed": [battle, 2, 3, 4]}
            r = server.send(req)
            if not r.get("ok"):
                stats["new failed"] += 1; continue
            lines = []
            if args.save_log:
                lines.append(f"battle {battle}   p1={args.p1} vs p2={args.p2}"
                             + (f"   mcts {args.ms} ms a decision" if "mcts" in (args.p1, args.p2) else ""))
                lines.append(f"  p1: {', '.join(names[0])}")
                lines.append(f"  p2: {', '.join(names[1])}")
            for turn in range(args.max_turns):
                reqs = r.get("requests", {})
                if not reqs:
                    break
                if args.save_log:
                    lines.append(f"\n  Turn {turn + 1}")
                r_prev = r
                choices = {"cmd": "choose"}
                for side, req in reqs.items():
                    name = args.p1 if side == "p1" else args.p2
                    if req.get("forceSwitch"):
                        choices[side] = forced_choice(req, rng)
                        continue
                    note = [] if args.save_log else None
                    if name == "mcts":
                        parts = policy_mcts(req, r["position"], side, rng, args.ms, stats, note,
                                            reqs)
                    elif name == "greedy":
                        parts = policy_greedy(req, r["position"], side, rng)
                    else:
                        parts = policy_random(req, r["position"], side, rng)
                    choices[side] = showdown_choice(req, parts)
                    if args.save_log:
                        detail = []
                        for slot, part in enumerate(parts):
                            if part and part[0] == "switch":
                                out = req["active"][slot]["species"]
                                inc = next((b["species"] for b in req["bench"]
                                            if b["slot"] == part[1]), f"#{part[1]}")
                                detail.append(f"slot{slot} {out} -> {inc}")
                        lines.append(f"    {side} {name}: {choices[side]}"
                                     + (f"   ({'; '.join(detail)})" if detail else ""))
                        lines.extend(note or [])
                r = server.send(choices)
                if not r.get("ok"):
                    # Any remaining legality corner (hidden trapping, a forme-specific rule)
                    # should cost a turn's policy, not the whole battle: retry once with a
                    # switch-free greedy choice for every side still owing one.
                    stats[f"retry after: {r.get('error','')}"] += 1
                    retry = {"cmd": "choose"}
                    for side2, req2 in reqs.items():
                        if req2.get("forceSwitch"):
                            retry[side2] = forced_choice(req2, rng)
                        else:
                            retry[side2] = showdown_choice(
                                req2, policy_greedy(req2, r_prev["position"], side2, rng))
                    r = server.send(retry)
                if args.save_log and r.get("ok"):
                    seen = None
                    for l in r.get("log", []):
                        if l == seen:      # battle.log itself repeats |switch| lines
                            continue
                        seen = l
                        lines.append("      " + readable(l))
                    for sd in r["position"]["sides"]:
                        lines.append(f"      after {sd['side']}: " + ", ".join(
                            f"{p['species']} {p['hp']}/{p['maxhp']}" for p in sd["active"] if p))
                if not r.get("ok"):
                    stats[f"rejected: {r.get('error','')}"] += 1
                    break
                if r.get("ended"):
                    wins[r.get("winner") or "draw"] += 1
                    if args.save_log:
                        lines.append(f"\n  RESULT: {r.get('winner') or 'draw'} wins")
                    break
            else:
                wins["turn limit"] += 1
                if args.save_log:
                    lines.append("\n  RESULT: turn limit")
            if args.save_log:
                d = Path(args.save_log); d.mkdir(parents=True, exist_ok=True)
                (d / f"{battle:03d}_{args.p1}_vs_{args.p2}.txt").write_text("\n".join(lines) + "\n")
    finally:
        server.close()

    n = sum(wins.values())
    print(f"p1={args.p1} vs p2={args.p2}   {n} battles decided of {args.battles}"
          + (f"   (mcts budget {args.ms} ms a decision)" if "mcts" in (args.p1, args.p2) else ""))
    for k in ("p1", "p2", "draw", "turn limit"):
        if wins[k]:
            print(f"   {k:11} {wins[k]:4}  ({100*wins[k]/n:.1f}%)" if n else f"   {k}: {wins[k]}")
    if stats["mcts decisions"]:
        print(f"   mcts decisions {stats['mcts decisions']}, mean visits "
              f"{stats['visits']/stats['mcts decisions']:.0f}")
    fb = {k: v for k, v in stats.items() if k.startswith("fallback") or k.startswith("rejected")
          or k.startswith("unparsed") or k.startswith("engine panic") or k.startswith("retry")}
    if fb:
        print("   fallbacks and rejections:")
        for k, v in sorted(fb.items(), key=lambda kv: -kv[1]):
            print(f"      {v:5}  {k}")


if __name__ == "__main__":
    main()
