#!/usr/bin/env python3
"""Translate Pokemon Showdown set data into what Reborn's engine can actually build.

Why this exists: the Smogon sample-team corpus (data.pkmn.cc) names things the way
Showdown displays them -- "Landorus-Therian", "Hidden Power Fire", "High Jump Kick" --
while Reborn addresses them by PBS internal name plus, for formes, a numeric form index
that lives in Scripts/MultipleForms.rb rather than in PBS at all. Four separate
conventions have to be reconciled, and three of them fail silently if you get them
wrong, which is why each is resolved from the game's own data rather than hardcoded.

The silent-failure traps, all verified against Reborn Yang's scripts:

  Stat order.  Showdown orders stats (hp, atk, def, spa, spd, spe). Essentials'
  PBStats is (HP, ATTACK, DEFENSE, SPEED, SPATK, SPDEF) -- Speed is index 3, not 5.
  A straight copy puts a Jolly sweeper's 252 Speed EVs into Special Attack.

  Hidden Power.  Reborn does NOT derive HP's type from IVs; the IV formula at
  PokeBattle_MoveEffects.rb:3901-3908 is commented out, replaced by a personalID
  lookup that also honours a preset `hptype` (attr_accessor, PokeBattle_Pokemon.rb:61).
  So "Hidden Power Fire" is the move HIDDENPOWER plus an explicit hptype -- breeding
  IVs for it, the way every other generation works, would do nothing here.

  Formes.  PBS pokemon.txt has no Therian entries; MultipleForms.rb carries
  `:FormName => {1 => "Therian"}` and, per forme, its own :Ability. A forme's ability
  slots are therefore not the base species' slots.

  Hyphens.  Kommo-o, Porygon-Z, Ho-Oh, Jangmo-o and Type: Null contain hyphens
  without being formes. Literal species names are matched before any suffix split.

Nothing here is Reborn-version-specific by assumption: every table is parsed from the
game files at the paths below, and a parse that comes back empty is fatal rather than
silently producing an empty mapping.
"""

import re
from pathlib import Path

STUDY = Path(__file__).resolve().parents[1]
GAME = STUDY.parent / "Reborn Yang" / "Reborn Yang"
PBS = GAME / "PBS" / "PBS"
SCRIPTS = GAME / "Scripts"

# Showdown EV/IV key -> PBStats index. Not the identity mapping; see module docstring.
STAT_INDEX = {"hp": 0, "atk": 1, "def": 2, "spe": 3, "spa": 4, "spd": 5}

NATURES = [
    "HARDY", "LONELY", "BRAVE", "ADAMANT", "NAUGHTY",
    "BOLD", "DOCILE", "RELAXED", "IMPISH", "LAX",
    "TIMID", "HASTY", "SERIOUS", "JOLLY", "NAIVE",
    "MODEST", "MILD", "QUIET", "BASHFUL", "RASH",
    "CALM", "GENTLE", "SASSY", "CAREFUL", "QUIRKY",
]

# Showdown display name -> PBS internal name, where the two genuinely differ in spelling
# rather than merely in punctuation (which norm() already handles).
MOVE_ALIASES = {"HIGHJUMPKICK": "HIJUMPKICK"}

# Formes Reborn does not model because they differ from the base species in nothing it
# simulates: same base stats, same ability, differing only in appearance or in carrying
# a signature move the base can also be taught. Showdown names them, so they arrive here
# and would otherwise be dropped as unknown formes.
#
# Deliberately NOT in this table: Greninja-Bond. Battle Bond is a real ability with real
# behaviour and Reborn has no BATTLEBOND at all, so folding it to base Greninja would
# quietly substitute Protean and change what the set does.
COSMETIC_FORMES = {("KELDEO", "RESOLUTE"), ("ZARUDE", "DADA")}


class Unrepresentable(Exception):
    """A set Reborn cannot build faithfully. The message is the reason, for reporting."""


def norm(name):
    """Fold a display name to its punctuation-free uppercase form: Ho-Oh -> HOOH."""
    return re.sub(r"[^A-Z0-9]", "", str(name).upper())


def _ini_records(path):
    """Yield {key: value} per [n] section of a PBS ini-style file."""
    record = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if line.startswith("["):
            if record:
                yield record
            record = {}
        elif "=" in line:
            key, value = line.split("=", 1)
            record[key.strip()] = value.strip()
    if record:
        yield record


def _csv_names(path):
    """PBS csv files (moves, items, abilities) are `id,INTERNALNAME,Display Name,...`."""
    out = set()
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split(",")
        if len(parts) > 2 and parts[0].strip().isdigit():
            out.add(norm(parts[1]))
    return out


def load_species():
    """internal name -> {"abilities": [slot0, slot1, hidden]}, from both PBS dex files."""
    out = {}
    for filename in ("pokemon.txt", "gen8pokemon.txt"):
        path = PBS / filename
        if not path.exists():
            continue
        for record in _ini_records(path):
            name = norm(record.get("InternalName", ""))
            if not name:
                continue
            slots = [None, None, None]
            regular = [norm(a) for a in record.get("Abilities", "").split(",") if a.strip()]
            for i in range(min(2, len(regular))):
                slots[i] = regular[i]
            hidden = [norm(a) for a in record.get("HiddenAbility", "").split(",") if a.strip()]
            slots[2] = hidden[0] if hidden else None
            out[name] = {"abilities": slots}
    return out


def _braced_body(source, start):
    """Text of the {...} block beginning at or after `start`, brace-matched.

    Forme bodies nest hashes and arrays several deep, so a non-greedy regex to the
    first closing brace silently truncates them -- which loses exactly the :Ability
    line this parser exists to read.
    """
    open_at = source.find("{", start)
    if open_at < 0:
        return ""
    depth = 0
    for i in range(open_at, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[open_at:i + 1]
    return source[open_at:]


def _forme_abilities(body):
    """Ability slots a forme declares, or None to inherit the base species'.

    MultipleForms writes this as `:Ability => PBAbilities::X` for a single-ability
    forme and `:Ability => [PBAbilities::X, PBAbilities::Y]` for a multi-slot one --
    same key, two shapes. Alolan Ninetales uses the second, and reading only the
    first form makes Snow Warning unreachable.
    """
    match = re.search(r":Abilit(?:y|ies)\s*=>\s*(\[[^\]]*\]|PBAbilities::[A-Z0-9_]+)", body)
    if not match:
        return None
    found = re.findall(r"PBAbilities::([A-Z0-9_]+)", match.group(1))
    return [norm(a) for a in found] or None


def load_formes():
    """species -> {FORMENAME: {"index": int, "abilities": [...] or None}}.

    Parsed from MultipleForms.rb, the only place form indices exist -- PBS has no
    entry for Landorus-Therian at all. A forme that declares its own abilities gets
    them, because setAbility indexes the forme's list, not the base species'.
    """
    source = (SCRIPTS / "MultipleForms.rb").read_text(encoding="utf-8", errors="replace")
    out = {}
    starts = [(m.start(), norm(m.group(1)))
              for m in re.finditer(r"PBSpecies::([A-Z0-9_]+)\s*=>\s*\{", source)]
    for i, (start, species) in enumerate(starts):
        end = starts[i + 1][0] if i + 1 < len(starts) else len(source)
        block = source[start:end]
        names = re.search(r":FormName\s*=>", block)
        if not names:
            continue
        formes = {}
        for index, label in re.findall(r'(\d+)\s*=>\s*"([^"]+)"',
                                       _braced_body(block, names.end())):
            body = re.search(r'"%s"\s*=>\s*\{' % re.escape(label), block)
            abilities = _forme_abilities(_braced_body(block, body.start())) if body else None
            formes[norm(label)] = {"index": int(index), "abilities": abilities}
        if formes:
            out[species] = formes
    return out


class Reborn:
    """Reborn's name universe, loaded once and queried per set."""

    def __init__(self):
        self.species = load_species()
        self.formes = load_formes()
        self.moves = _csv_names(PBS / "moves.txt")
        self.items = _csv_names(PBS / "items.txt")
        self.abilities = _csv_names(PBS / "abilities.txt")
        # types.txt is ini-style, not csv like the three above.
        self.types = {norm(r["InternalName"]) for r in _ini_records(PBS / "types.txt")
                      if r.get("InternalName")}
        for label, table in (("species", self.species), ("formes", self.formes),
                             ("moves", self.moves), ("items", self.items),
                             ("abilities", self.abilities), ("types", self.types)):
            if not table:
                raise SystemExit(f"parsed no {label} from {GAME}; check the game path")

    def resolve_species(self, display):
        """-> (internal name, form index, ability slots). Literal names win over splits."""
        literal = norm(display)
        if literal in self.species:
            return literal, 0, self.species[literal]["abilities"]
        if "-" not in display:
            raise Unrepresentable(f"unknown species {display}")
        base = norm(display.split("-")[0])
        suffix = norm(display.split("-", 1)[1])
        if base not in self.species:
            raise Unrepresentable(f"unknown species {display}")
        if (base, suffix) in COSMETIC_FORMES:
            return base, 0, self.species[base]["abilities"]
        for name, forme in self.formes.get(base, {}).items():
            if name == suffix or suffix in name or name in suffix:
                slots = forme["abilities"]
                if slots:
                    slots = slots + [None] * (3 - len(slots))
                return base, forme["index"], slots or self.species[base]["abilities"]
        raise Unrepresentable(f"no forme {suffix} for {base}")

    def resolve_move(self, display):
        """-> (internal name, hidden-power type or None)."""
        folded = norm(display)
        if folded.startswith("HIDDENPOWER"):
            if "HIDDENPOWER" not in self.moves:
                raise Unrepresentable("no HIDDENPOWER move")
            hp_type = folded[len("HIDDENPOWER"):]
            if hp_type and hp_type not in self.types:
                raise Unrepresentable(f"unknown Hidden Power type {hp_type}")
            return "HIDDENPOWER", hp_type or None
        folded = MOVE_ALIASES.get(folded, folded)
        if folded not in self.moves:
            raise Unrepresentable(f"unknown move {display}")
        return folded, None

    def resolve_set(self, showdown):
        """A Showdown JSON set -> the fields make_party needs, or Unrepresentable."""
        species, form, ability_slots = self.resolve_species(showdown["species"])

        moves, hptype = [], None
        for move in showdown.get("moves", []):
            internal, kind = self.resolve_move(move)
            if internal in moves:      # Showdown allows no duplicate moves; a repeat
                continue               # after HP-collapse means two HP variants.
            moves.append(internal)
            hptype = hptype or kind
        if not moves:
            raise Unrepresentable("no moves")

        item = None
        if showdown.get("item"):
            item = norm(showdown["item"])
            if item not in self.items:
                raise Unrepresentable(f"unknown item {showdown['item']}")

        ability_slot = 0
        if showdown.get("ability"):
            wanted = norm(showdown["ability"])
            if wanted not in self.abilities:
                raise Unrepresentable(f"unknown ability {showdown['ability']}")
            if wanted not in [a for a in ability_slots if a]:
                raise Unrepresentable(
                    f"{showdown['ability']} is not a slot of {showdown['species']}")
            ability_slot = ability_slots.index(wanted)

        nature = 0
        if showdown.get("nature"):
            wanted = norm(showdown["nature"])
            if wanted not in NATURES:
                raise Unrepresentable(f"unknown nature {showdown['nature']}")
            nature = NATURES.index(wanted)

        evs = [0] * 6
        for key, value in (showdown.get("evs") or {}).items():
            if key in STAT_INDEX:
                evs[STAT_INDEX[key]] = int(value)
        ivs = [31] * 6
        for key, value in (showdown.get("ivs") or {}).items():
            if key in STAT_INDEX:
                ivs[STAT_INDEX[key]] = int(value)

        return {
            "species": species, "form": form, "moves": moves, "item": item,
            "ability": ability_slot, "nature": nature, "evs": evs, "ivs": ivs,
            "hptype": hptype,
        }
