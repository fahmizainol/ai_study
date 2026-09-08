#!/usr/bin/env python3
"""Run pmariglia's poke-engine search on decisions the Realidea adapter hands over.

The other half of the 0.8.0 bridge (adapters/realidea/Portable_AI_Adapter.rb, module
FoulPlay). The adapter writes Data/ai_foulplay_state.json for every voluntary
decision an actor with foul_play=true faces; this process watches for it, builds a
poke_engine State from it, runs monte_carlo_tree_search for the requested number of
iterations, and writes Data/ai_foulplay_reply.txt naming the most-visited choice as a
slot the adapter can register. Files travel through temp names and os.replace, so
neither side reads a half-written one.

    tools/foul_play_sidecar.py --game "<dir containing Data/>" [--iterations N] [--check]
    tools/foul_play_sidecar.py --once state.json [--check]       one state, print the reply
    tools/foul_play_sidecar.py --extract-ids <poke-engine clone>  refresh the id list

Needs the gen 6 build of poke_engine importable: tools/build_poke_engine.sh makes a
venv with it. Everything the engine does not know is written to
Data/ai_foulplay_log.txt rather than silently mapped -- poke-engine's own parsers fall
back to NONE / UNKNOWNITEM for an unknown name, which would turn a bad export into a
quiet bad plan, so every id is checked against generated/poke_engine_ids_gen6.json
first.

--check prices the on-field pair's moves with poke-engine's calculate_damage and
writes the comparison with the adapter's own cells (both are the maximum roll) to
Data/ai_foulplay_check.ndjson. That file is the measurement of how far Showdown's
gen 6 is from this engine, decision by decision.
"""

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

STUDY = Path(__file__).resolve().parents[1]
IDS_FILE = STUDY / "generated" / "poke_engine_ids_gen6.json"

STATE_NAME = "ai_foulplay_state.json"
REPLY_NAME = "ai_foulplay_reply.txt"
LOG_NAME = "ai_foulplay_log.txt"
CHECK_NAME = "ai_foulplay_check.ndjson"

# Realidea's forme index -> the suffix poke-engine's PokemonName carries. The same
# table showdown_names.py audits against the game (Realidea.FORME_TABLE), read in the
# other direction.
FORMES = {
    "ROTOM": {1: "HEAT", 2: "WASH", 3: "FROST", 4: "FAN", 5: "MOW"},
    "LANDORUS": {1: "THERIAN"},
    "THUNDURUS": {1: "THERIAN"},
    "TORNADUS": {1: "THERIAN"},
    "KYUREM": {1: "WHITE", 2: "BLACK"},
}
# Species whose two megas are told apart by forme index (125_Pokemon_MegaEvolution.rb).
MEGA_XY = {"CHARIZARD", "MEWTWO"}


def extract_ids(clone):
    """Read every id enum out of the poke-engine source. Regenerates IDS_FILE."""
    src = Path(clone) / "src"
    wanted = [
        ("pokemon", "pokemon.rs", "PokemonName"),
        ("moves", "choices.rs", "Choices"),
        ("abilities", "genx/abilities.rs", "Abilities"),
        ("items", "genx/items.rs", "Items"),
        ("volatiles", "genx/state.rs", "PokemonVolatileStatus"),
        ("weather", "genx/state.rs", "Weather"),
        ("terrain", "genx/state.rs", "Terrain"),
        ("status", "state.rs", "PokemonStatus"),
        ("natures", "state.rs", "PokemonNature"),
        ("types", "state.rs", "PokemonType"),
    ]
    out = {}
    for key, rel, name in wanted:
        text = (src / rel).read_text(encoding="utf-8")
        match = re.search(r"\n\s*%s \{\n(.*?)\n\s*\}" % name, text, re.S)
        if not match:
            raise SystemExit(f"{rel}: no enum {name}")
        out[key] = [line.strip().rstrip(",") for line in match.group(1).split("\n")
                    if line.strip() and not line.strip().startswith("//")]
    return out


def load_ids(path=IDS_FILE):
    with open(path, encoding="utf-8") as handle:
        return {key: set(values) for key, values in json.load(handle).items()}


class Problems(list):
    """Unknown ids and unrepresentable facts met while building one state."""

    def add(self, text):
        if text not in self:
            self.append(text)


def species_id(mon, ids, problems):
    base = mon.get("species") or "NONE"
    form = int(mon.get("form") or 0)
    if mon.get("mega"):
        candidate = base + "MEGA"
        if base in MEGA_XY:
            candidate += "X" if form == 1 else "Y"
    elif form > 0:
        suffix = FORMES.get(base, {}).get(form)
        candidate = base + suffix if suffix else base
        if not suffix:
            problems.add(f"species {base} form {form} has no poke-engine forme; using base")
    else:
        candidate = base
    if candidate not in ids["pokemon"]:
        problems.add(f"species {candidate} unknown to poke-engine")
        return "NONE"
    return candidate


def move_id(entry, ids, problems):
    key = entry.get("id") or "NONE"
    if key == "HIDDENPOWER" and entry.get("hp_type"):
        power = 70 if int(entry.get("hp_power") or 60) >= 65 else 60
        candidate = f"HIDDENPOWER{entry['hp_type']}{power}"
        if candidate in ids["moves"]:
            return candidate
        problems.add(f"move {candidate} unknown to poke-engine; using HIDDENPOWER")
        return "HIDDENPOWER"
    if key not in ids["moves"]:
        problems.add(f"move {key} unknown to poke-engine")
        return "NONE"
    return key


def named(kind, value, ids, problems, fallback):
    if not value:
        return fallback
    if value not in ids[kind]:
        problems.add(f"{kind[:-1] if kind.endswith('s') else kind} {value} unknown to poke-engine")
        return fallback
    return value


def status_of(mon, toxic_count):
    status = mon.get("status") or "none"
    if status == "poison" and toxic_count > 0:
        return "toxic"
    return status


def build_pokemon(mon, ids, problems, on_field, toxic_count):
    import poke_engine as pe

    moves = []
    for entry in mon.get("moves") or []:
        moves.append(pe.Move(id=move_id(entry, ids, problems).lower(),
                             pp=int(entry.get("pp") or 0),
                             disabled=bool(entry.get("disabled")) if on_field else False))
    types = list(mon.get("types") or ["TYPELESS", "TYPELESS"])
    types = [named("types", t, ids, problems, "TYPELESS") for t in types][:2]
    while len(types) < 2:
        types.append("TYPELESS")
    evs = list(mon.get("evs") or [0] * 6)[:6]
    while len(evs) < 6:
        evs.append(0)
    status = status_of(mon, toxic_count if on_field else 0)
    if status.upper() not in ids["status"]:
        problems.add(f"status {status} unknown to poke-engine")
        status = "none"
    count = int(mon.get("status_count") or 0)
    # Essentials counts sleep turns DOWN (statusCount = turns left); poke-engine counts
    # turns slept UP from 0 against a gen 6 maximum of three.
    sleep_turns = max(0, 3 - count) if status == "sleep" and count > 0 else 0
    return pe.Pokemon(
        id=species_id(mon, ids, problems).lower(),
        level=int(mon.get("level") or 100),
        types=(types[0].lower(), types[1].lower()),
        base_types=(types[0].lower(), types[1].lower()),
        hp=int(mon.get("hp") or 0),
        maxhp=int(mon.get("maxhp") or 1),
        ability=named("abilities", mon.get("ability"), ids, problems, "NONE").lower(),
        base_ability=named("abilities", mon.get("ability"), ids, problems, "NONE").lower(),
        item=named("items", mon.get("item"), ids, problems, "NONE").lower(),
        nature=named("natures", mon.get("nature"), ids, problems, "SERIOUS").lower(),
        evs=tuple(int(v) for v in evs),
        attack=int(mon.get("attack") or 1),
        defense=int(mon.get("defense") or 1),
        special_attack=int(mon.get("special_attack") or 1),
        special_defense=int(mon.get("special_defense") or 1),
        speed=int(mon.get("speed") or 1),
        status=status.lower(),
        sleep_turns=sleep_turns,
        weight_kg=float(mon.get("weight_kg") or 0.0),
        moves=moves,
        mega_evolved=bool(mon.get("mega")),
    )


# Essentials keeps a volatile's TURNS REMAINING; poke-engine keeps turns ELAPSED and
# panics outright when a live volatile carries a duration past its own maximum
# (generate_instructions.rs: Taunt 0..2, Encore 0..2, locked move 0..2, Yawn 0..1).
# Slow Start is the one counter it runs down, so it passes through. A conversion
# that lands outside the range clamps to the last valid turn rather than crash.
ELAPSED_MAX = {"taunt": (3, 2), "encore": (3, 2), "lockedmove": (3, 2), "yawn": (2, 1)}


def durations_for(doc_durations):
    out = {}
    for key, value in (doc_durations or {}).items():
        value = int(value or 0)
        if key in ELAPSED_MAX:
            total, top = ELAPSED_MAX[key]
            out[key] = min(top, max(0, total - value)) if value > 0 else 0
        else:
            out[key] = max(0, value)
    return out


def build_side(doc_side, ids, problems):
    import poke_engine as pe

    active = int(doc_side.get("active") or 0)
    toxic_count = int(doc_side.get("toxic_count") or 0)
    mons = doc_side.get("pokemon") or []
    pokemon = [build_pokemon(mon, ids, problems, i == active, toxic_count)
               for i, mon in enumerate(mons)]
    while len(pokemon) < 6:
        pokemon.append(pe.Pokemon.create_fainted())
    conditions = dict(doc_side.get("conditions") or {})
    conditions["toxic_count"] = toxic_count
    volatiles = set()
    for name in doc_side.get("volatiles") or []:
        if name in ids["volatiles"]:
            volatiles.add(name.lower())
        else:
            problems.add(f"volatile {name} unknown to poke-engine")
    boosts = doc_side.get("boosts") or {}
    durations = doc_side.get("durations") or {}
    wish = doc_side.get("wish") or [0, 0]
    return pe.Side(
        pokemon=pokemon,
        active_index=str(active),
        side_conditions=pe.SideConditions(**conditions),
        volatile_statuses=volatiles,
        volatile_status_durations=pe.VolatileStatusDurations(**durations_for(durations)),
        substitute_health=int(doc_side.get("substitute_health") or 0),
        wish=(int(wish[0]), int(wish[1])),
        force_trapped=bool(doc_side.get("trapped")),
        last_used_move=doc_side.get("last_used_move") or "move:none",
        attack_boost=int(boosts.get("attack") or 0),
        defense_boost=int(boosts.get("defense") or 0),
        special_attack_boost=int(boosts.get("special_attack") or 0),
        special_defense_boost=int(boosts.get("special_defense") or 0),
        speed_boost=int(boosts.get("speed") or 0),
        accuracy_boost=int(boosts.get("accuracy") or 0),
        evasion_boost=int(boosts.get("evasion") or 0),
    )


def build_state(doc, ids, problems):
    import poke_engine as pe

    weather = (doc.get("weather") or "none").upper()
    if weather not in ids["weather"]:
        problems.add(f"weather {weather} unknown to poke-engine")
        weather = "NONE"
    terrain = doc.get("terrain") or ["none", 0]
    terrain_name = str(terrain[0]).upper()
    if terrain_name not in ids["terrain"]:
        problems.add(f"terrain {terrain_name} unknown to poke-engine")
        terrain_name, terrain = "NONE", ["none", 0]
    return pe.State(
        side_one=build_side(doc["side_one"], ids, problems),
        side_two=build_side(doc["side_two"], ids, problems),
        weather=weather.lower(),
        weather_turns_remaining=int(doc.get("weather_turns") or 0),
        terrain=terrain_name.lower(),
        terrain_turns_remaining=int(terrain[1] or 0),
        trick_room=bool(doc.get("trick_room")),
        trick_room_turns_remaining=int(doc.get("trick_room_turns") or 0),
    )


def label_for(choice, doc_side, state_side):
    """poke-engine's move_choice string -> 'move:<slot>' | 'switch:<party slot>'."""
    text = choice.lower()
    if text.startswith("switch "):
        wanted = text[len("switch "):]
        active = int(doc_side.get("active") or 0)
        for i, mon in enumerate(state_side.pokemon):
            if i != active and mon.id == wanted and mon.hp > 0:
                return f"switch:{i}"
        return None
    for suffix in ("-mega", "-tera"):
        if text.endswith(suffix):
            text = text[:-len(suffix)]
    active = state_side.pokemon[int(doc_side.get("active") or 0)]
    for slot, move in enumerate(active.moves):
        if move.id == text:
            return f"move:{slot}"
    return None


def search(doc, state, iterations):
    import poke_engine as pe

    result = pe.monte_carlo_tree_search(state, iterations=iterations)
    own = []
    for entry in result.side_one:
        label = label_for(entry.move_choice, doc["side_one"], state.side_one)
        own.append((label or entry.move_choice, entry.visits, entry.total_score))
    foe = [(label_for(e.move_choice, doc["side_two"], state.side_two) or e.move_choice, e.visits)
           for e in result.side_two]
    best = max(own, key=lambda item: item[1])
    return best, own, foe, result.total_visits


def reply_text(best, own, foe, total, iterations):
    label, visits, score = best
    kind, _, slot = label.partition(":")
    lines = [
        f"type={kind}",
        f"slot={slot}",
        f"visits={visits}",
        f"score={(score / visits) if visits else 0.0:.6f}",
        f"iterations={iterations}",
        f"total={total}",
        "own=" + ",".join(f"{l}:{v}" for l, v, _ in own),
        "foe=" + ",".join(f"{l}:{v}" for l, v in foe),
    ]
    return "\n".join(lines) + "\n"


def damage_check(doc, state, ids):
    """Price the on-field pair's moves both ways and pair them with the adapter's cells."""
    import poke_engine as pe

    cells = doc.get("cells") or {}
    out = []
    own_active = state.side_one.pokemon[int(doc["side_one"].get("active") or 0)]
    foe_active = state.side_two.pokemon[int(doc["side_two"].get("active") or 0)]
    own_moves = [m.id for m in own_active.moves if m.id != "none"]
    foe_moves = [m.id for m in foe_active.moves if m.id != "none"]
    if not own_moves or not foe_moves:
        return out
    problems = Problems()

    def engine_id(entry_key, side_doc):
        for entry in side_doc["pokemon"][int(side_doc.get("active") or 0)].get("moves") or []:
            if entry.get("id") == entry_key:
                return move_id(entry, ids, problems).lower()
        return None

    for direction, key, first in (("out", "out_moves", True), ("in", "in_moves", False)):
        table = cells.get(key) or {}
        for move_key, cell in table.items():
            if not cell or not cell.get("damaging"):
                continue
            engine = engine_id(move_key, doc["side_one" if first else "side_two"])
            if not engine:
                continue
            try:
                if first:
                    rolls, _ = pe.calculate_damage(state, engine, foe_moves[0], True)
                    target_hp = foe_active.maxhp
                else:
                    _, rolls = pe.calculate_damage(state, own_moves[0], engine, True)
                    target_hp = own_active.maxhp
            except Exception as error:  # noqa: BLE001 - one bad pair must not stop the check
                out.append({"direction": direction, "move": move_key, "error": str(error)})
                continue
            # calculate_damage returns [max roll, max roll on a crit]; the cell is the
            # max roll with no crit (pbRoughDamage has neither factor), so the first
            # entry is the like-for-like number.
            rolls = list(rolls or [])
            engine_pct = (rolls[0] * 100.0 / target_hp) if rolls and target_hp else None
            cell_pct = cell.get("pct")
            out.append({
                "turn": doc.get("turn"), "direction": direction, "move": move_key,
                "attacker": (own_active if first else foe_active).id,
                "defender": (foe_active if first else own_active).id,
                "engine_max_pct": engine_pct, "engine_crit_pct": (rolls[1] * 100.0 / target_hp) if len(rolls) > 1 and target_hp else None,
                "cell_pct": cell_pct,
                "diff": (engine_pct - cell_pct) if engine_pct is not None and cell_pct is not None else None,
                # pbRoughDamage floors an immune hit at 1 HP (085:3608); a sub-1% cell
                # against an engine zero is that floor, not a mechanics disagreement.
                "cell_floor": bool(engine_pct == 0 and cell_pct is not None and 0 < cell_pct < 1.0),
            })
    return out


def log(data_dir, line):
    with open(data_dir / LOG_NAME, "a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def write_atomic(path, text):
    tmp = path.with_suffix(path.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    os.replace(tmp, path)


def handle_state(doc, ids, iterations, check, data_dir=None):
    problems = Problems()
    state = build_state(doc, ids, problems)
    wanted = int(iterations or doc.get("iterations") or 5000)
    started = time.time()
    best, own, foe, total = search(doc, state, wanted)
    elapsed = time.time() - started
    if data_dir is not None:
        for problem in problems:
            log(data_dir, f"turn={doc.get('turn')} {problem}")
        if check:
            with open(data_dir / CHECK_NAME, "a", encoding="utf-8") as handle:
                for row in damage_check(doc, state, ids):
                    handle.write(json.dumps(row) + "\n")
    return reply_text(best, own, foe, total, wanted), elapsed, problems


def serve(game_dir, iterations, check, keep_states=None, poll=0.004):
    data_dir = Path(game_dir) / "Data"
    state_path = data_dir / STATE_NAME
    reply_path = data_dir / REPLY_NAME
    ids = load_ids()
    if keep_states:
        Path(keep_states).mkdir(parents=True, exist_ok=True)
    print(f"foul_play sidecar watching {state_path}", flush=True)
    decisions = 0
    while True:
        if not state_path.exists():
            time.sleep(poll)
            continue
        try:
            with open(state_path, encoding="utf-8") as handle:
                doc = json.load(handle)
        except (OSError, ValueError):
            time.sleep(poll)
            continue
        try:
            state_path.unlink()
        except OSError:
            pass
        if keep_states:
            with open(Path(keep_states) / f"state_{decisions:05d}.json", "w", encoding="utf-8") as handle:
                json.dump(doc, handle)
        try:
            text, elapsed, problems = handle_state(doc, ids, iterations, check, data_dir)
        except (KeyboardInterrupt, SystemExit):
            raise
        except BaseException as error:  # noqa: BLE001 - a Rust panic arrives as a BaseException
            # Answer at once with an error so the adapter hands the turn to the rules
            # now, not after its timeout; the state that did it is kept for the fix.
            log(data_dir, f"turn={doc.get('turn')} sidecar error {type(error).__name__}: {error}")
            if keep_states:
                with open(Path(keep_states) / f"crash_{decisions:05d}.json", "w", encoding="utf-8") as handle:
                    json.dump(doc, handle)
            text = f"type=error\nmessage={type(error).__name__}: {str(error).splitlines()[0] if str(error) else ''}\n"
        write_atomic(reply_path, text)
        decisions += 1
        if decisions % 50 == 0:
            print(f"{decisions} decisions, last {elapsed * 1000:.0f} ms", flush=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--game", help="game directory (the one containing Data/)")
    parser.add_argument("--once", help="process one exported state file and print the reply")
    parser.add_argument("--iterations", type=int, help="override the iterations the state asks for")
    parser.add_argument("--check", action="store_true", help="also write the damage comparison")
    parser.add_argument("--extract-ids", metavar="CLONE", help="rebuild the id list from a poke-engine clone")
    parser.add_argument("--keep-states", metavar="DIR", help="save every exported state under DIR (serve mode)")
    args = parser.parse_args(argv)
    if args.extract_ids:
        ids = extract_ids(args.extract_ids)
        with open(IDS_FILE, "w", encoding="utf-8") as handle:
            json.dump(ids, handle)
        print({key: len(values) for key, values in ids.items()})
        return 0
    if args.once:
        with open(args.once, encoding="utf-8") as handle:
            doc = json.load(handle)
        ids = load_ids()
        text, elapsed, problems = handle_state(doc, ids, args.iterations, False)
        sys.stdout.write(text)
        for problem in problems:
            print("problem:", problem)
        if args.check:
            state = build_state(doc, ids, Problems())
            for row in damage_check(doc, state, ids):
                print(json.dumps(row))
        print(f"{elapsed * 1000:.0f} ms")
        return 0
    if not args.game:
        parser.error("--game or --once is required")
    serve(args.game, args.iterations, args.check, args.keep_states)
    return 0


if __name__ == "__main__":
    sys.exit(main())
