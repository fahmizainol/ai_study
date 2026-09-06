#!/usr/bin/env python3
"""Translate Pokemon Showdown set data into what a fangame's engine can actually build.

Why this exists: the Smogon sample-team corpus (data.pkmn.cc) names things the way
Showdown displays them -- "Landorus-Therian", "Hidden Power Fire", "High Jump Kick" --
while an Essentials engine addresses them by PBS internal name plus, for formes, a
numeric form index that lives in a script rather than in PBS at all. Several separate
conventions have to be reconciled, and most of them fail silently if you get them
wrong, which is why each is resolved from the game's own data rather than hardcoded.

Two engines are modelled, because the study measures the same corpus against both:

    Reborn      Reborn Yang, an E19.16 fork    gen 6-8 teams
    Realidea    Realidea V4.1, Essentials v16  gen 6 teams only (see Realidea.veto)

The silent-failure traps, each verified against the game it applies to:

  Stat order (both).  Showdown orders stats (hp, atk, def, spa, spd, spe). Essentials'
  PBStats is (HP, ATTACK, DEFENSE, SPEED, SPATK, SPDEF) -- Speed is index 3, not 5.
  A straight copy puts a Jolly sweeper's 252 Speed EVs into Special Attack.

  Hidden Power (differently in each).  Reborn does NOT derive HP's type from IVs; the
  IV formula at PokeBattle_MoveEffects.rb:3901-3908 is commented out, replaced by a
  personalID lookup that also honours a preset `hptype` (attr_accessor,
  PokeBattle_Pokemon.rb:61). So there, "Hidden Power Fire" is the move plus an explicit
  hptype. Realidea keeps the real IV formula and has no hptype field at all -- and its
  type pool is 17 wide, not 16, so a Showdown IV spread lands on the WRONG type. See
  Realidea.finalise_hidden_power.

  Formes.  PBS has no entry for Landorus-Therian at all. Reborn's MultipleForms.rb
  carries `:FormName => {1 => "Therian"}` and can be parsed; Realidea's names its formes
  only in Spanish comments, so its table is written out and machine-checked instead.

  Hyphens.  Kommo-o, Porygon-Z, Ho-Oh, Jangmo-o and Type: Null contain hyphens without
  being formes. Literal species names are matched before any suffix split.

  Items and abilities that exist but do nothing.  A name resolving is not the same as
  the mechanic existing. Realidea ships all 29 Z-crystals as items and BATTLEBOND as an
  ability, and implements neither -- importing those sets would quietly hand a mon an
  inert item. `veto` rejects them; see that method for what it costs.

Nothing here is version-specific by assumption: every table is parsed from the game
files at the paths below, and a parse that comes back empty is fatal rather than
silently producing an empty mapping.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_rxdata

STUDY = Path(__file__).resolve().parents[1]
GAMES = STUDY.parent

# Showdown EV/IV key -> PBStats index. Not the identity mapping; see module docstring.
STAT_INDEX = {"hp": 0, "atk": 1, "def": 2, "spe": 3, "spa": 4, "spd": 5}

NATURES = [
    "HARDY", "LONELY", "BRAVE", "ADAMANT", "NAUGHTY",
    "BOLD", "DOCILE", "RELAXED", "IMPISH", "LAX",
    "TIMID", "HASTY", "SERIOUS", "JOLLY", "NAIVE",
    "MODEST", "MILD", "QUIET", "BASHFUL", "RASH",
    "CALM", "GENTLE", "SASSY", "CAREFUL", "QUIRKY",
]


class Unrepresentable(Exception):
    """A set the engine cannot build faithfully. The message is the reason, for reporting."""


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


class Game:
    """One engine's name universe, loaded once and queried per set.

    Subclasses supply the paths, the forme table, and whatever that engine gets wrong
    about Hidden Power. Everything else is shared, because everything else is just
    Essentials.
    """

    NAME = None
    DEX_FILES = ("pokemon.txt",)
    # Display name -> PBS internal name, where the two genuinely differ in spelling
    # rather than merely in punctuation (which norm() already handles).
    MOVE_ALIASES = {}
    # Formes the engine does not model because they differ from the base species in
    # nothing it simulates: same base stats, same ability, differing only in appearance
    # or in carrying a signature move the base can also be taught. Showdown names them,
    # so they arrive here and would otherwise be dropped as unknown formes.
    COSMETIC_FORMES = frozenset()

    def __init__(self):
        self.species = self.load_species()
        self.formes = self.load_formes()
        self.moves = _csv_names(self.PBS / "moves.txt")
        self.items = _csv_names(self.PBS / "items.txt")
        self.abilities = _csv_names(self.PBS / "abilities.txt")
        # types.txt is ini-style, not csv like the three above.
        self.types = {norm(r["InternalName"]) for r in _ini_records(self.PBS / "types.txt")
                      if r.get("InternalName")}
        for label, table in (("species", self.species), ("formes", self.formes),
                             ("moves", self.moves), ("items", self.items),
                             ("abilities", self.abilities), ("types", self.types)):
            if not table:
                raise SystemExit(f"parsed no {label} from {self.GAME}; check the game path")

    def load_species(self):
        """internal name -> {"abilities": [slot0, slot1, hidden]}, from the dex files."""
        out = {}
        for filename in self.DEX_FILES:
            path = self.PBS / filename
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

    def load_formes(self):
        raise NotImplementedError

    def veto(self, showdown):
        """Reason this set is unbuildable for reasons no table catches, or None."""
        return None

    def finalise_hidden_power(self, ivs, hptype):
        """-> (ivs, hptype), letting an engine express Hidden Power its own way."""
        return ivs, hptype

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
        if (base, suffix) in self.COSMETIC_FORMES:
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
        folded = self.MOVE_ALIASES.get(folded, folded)
        if folded not in self.moves:
            raise Unrepresentable(f"unknown move {display}")
        return folded, None

    def resolve_set(self, showdown):
        """A Showdown JSON set -> the fields make_party needs, or Unrepresentable."""
        blocked = self.veto(showdown)
        if blocked:
            raise Unrepresentable(blocked)
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
        ivs, hptype = self.finalise_hidden_power(ivs, hptype)

        return {
            "species": species, "form": form, "moves": moves, "item": item,
            "ability": ability_slot, "nature": nature, "evs": evs, "ivs": ivs,
            "hptype": hptype,
        }


class Reborn(Game):
    """Reborn Yang: an E19.16 fork, gen-7-era with gen 8 additions."""

    NAME = "reborn"
    GAME = GAMES / "Reborn Yang" / "Reborn Yang"
    PBS = GAME / "PBS" / "PBS"
    SCRIPTS = GAME / "Scripts"
    DEX_FILES = ("pokemon.txt", "gen8pokemon.txt")
    MOVE_ALIASES = {"HIGHJUMPKICK": "HIJUMPKICK"}
    # Deliberately NOT in this table: Greninja-Bond. Battle Bond is a real ability with
    # real behaviour and Reborn has no BATTLEBOND at all, so folding it to base Greninja
    # would quietly substitute Protean and change what the set does.
    COSMETIC_FORMES = frozenset({("KELDEO", "RESOLUTE"), ("ZARUDE", "DADA")})

    def load_formes(self):
        """species -> {FORMENAME: {"index": int, "abilities": [...] or None}}.

        Parsed from MultipleForms.rb, the only place form indices exist -- PBS has no
        entry for Landorus-Therian at all. A forme that declares its own abilities gets
        them, because setAbility indexes the forme's list, not the base species'.
        """
        source = (self.SCRIPTS / "MultipleForms.rb").read_text(encoding="utf-8",
                                                               errors="replace")
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


class Realidea(Game):
    """Realidea V4.1: Essentials v16, a mega-era engine with a gen 7 dex bolted on."""

    NAME = "realidea"
    GAME = GAMES / "Realidea V4.1"
    PBS = GAME / "PBS"
    BUNDLE = GAME / "Data" / "Scripts.rxdata"

    # Realidea's MultipleForms names its formes only in Spanish comments -- there is no
    # :FormName key anywhere in the section -- so the Reborn parser has nothing to read
    # and this table is written out instead. It is not trusted on its word: _audit()
    # re-reads the game's own script and fails loudly if a species stops registering
    # formes or an ability named here disappears from its block.
    #
    # Ability slots follow the engine's own convention (PokeBattle_Pokemon#ability,
    # 123:239): getAbilityList yields [id, slot] pairs and slot 2 is the hidden one, so
    # a forme with only slots 0 and 2 has a genuine hole at 1. Rotom is absent because
    # its block overrides no abilities -- every appliance keeps base Rotom's Levitate.
    FORME_TABLE = {
        "LANDORUS":  {"THERIAN": (1, ["INTIMIDATE", None, "SHEERFORCE"])},
        "THUNDURUS": {"THERIAN": (1, ["VOLTABSORB", None, "DEFIANT"])},
        "TORNADUS":  {"THERIAN": (1, ["REGENERATOR", None, "DEFIANT"])},
        "ROTOM":     {"HEAT": (1, None), "WASH": (2, None), "FROST": (3, None),
                      "FAN": (4, None), "MOW": (5, None)},
        "KYUREM":    {"WHITE": (1, ["TURBOBLAZE", None, None]),
                      "BLACK": (2, ["TERAVOLT", None, None])},
    }

    # Hidden Power's 17-wide type pool, in PBTypes id order: every non-pseudo type
    # except NORMAL and SHADOW, which is what pbHiddenPower enumerates
    # (PokeBattle_MoveEffects.rb:3764-3770). Sixteen types wide everywhere else --
    # FAIRY is the extra, and it is what shifts the mapping. Checked against
    # PBS/types.txt at load time.
    HP_POOL = ["FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST",
               "STEEL", "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC", "ICE",
               "DRAGON", "DARK", "FAIRY"]
    # Which IV to sacrifice first when a parity has to change. Each flip moves one stat
    # by exactly one point at level 100, so this barely matters -- but Speed is last
    # because a speed tie is the one place one point is not noise.
    HP_FLIP_ORDER = [0, 5, 2, 1, 4, 3]

    def __init__(self):
        Game.__init__(self)
        self._audit()

    def _script(self, name):
        for section, source in extract_rxdata.sections(str(self.BUNDLE)):
            if section == name:
                return source
        raise SystemExit(f"{self.BUNDLE} has no {name} section")

    def load_formes(self):
        return {species: {name: {"index": index, "abilities": abilities}
                          for name, (index, abilities) in formes.items()}
                for species, formes in self.FORME_TABLE.items()}

    def _audit(self):
        """Fail loudly if the hand-written tables have drifted from the game."""
        source = self._script("Pokemon_MultipleForms")
        for species, formes in self.FORME_TABLE.items():
            match = re.search(r"MultipleForms\.register\(:%s,\s*\{" % species, source)
            if not match:
                raise SystemExit(f"Realidea no longer registers formes for {species}")
            block = _braced_body(source, match.start())
            for name, (_, abilities) in formes.items():
                for ability in [a for a in (abilities or []) if a]:
                    if ability not in norm(block):
                        raise SystemExit(
                            f"Realidea's {species} block no longer names {ability} "
                            f"(forme {name}); FORME_TABLE is stale")
        pool = [norm(r["InternalName"]) for r in _ini_records(self.PBS / "types.txt")
                if r.get("InternalName")
                and str(r.get("IsPseudoType", "")).lower() != "true"
                and norm(r["InternalName"]) not in ("NORMAL", "SHADOW")]
        if pool != self.HP_POOL:
            raise SystemExit(f"Realidea's Hidden Power pool changed: {pool}")

    def _hp_type(self, ivs):
        """Realidea's own formula, PokeBattle_MoveEffects.rb:3760-3784."""
        parity = sum((ivs[i] & 1) << i for i in range(6))
        return self.HP_POOL[(parity * (len(self.HP_POOL) - 1)) // 63]

    def veto(self, showdown):
        """Names that resolve against a mechanic the engine never implemented.

        Both cost real teams and both are worth it: importing them would hand a mon an
        item or an ability that does nothing, and the result would read as a fair test
        of a team it is not. The Z-crystal veto is what confines this engine's tier
        suite to gen 6 -- 24 of gen7ou's 26 sample teams carry one.
        """
        item = norm(showdown.get("item") or "")
        if item.endswith("IUMZ") and item in self.items:
            return f"{showdown['item']}: Realidea has Z-crystals as items but no Z-move engine"
        if norm(showdown.get("ability") or "") == "BATTLEBOND":
            return "Battle Bond: the ability exists in PBS but nothing in the engine reads it"
        return None

    def finalise_hidden_power(self, ivs, hptype):
        """Solve the IVs for the type, because this engine has no hptype field.

        Realidea derives Hidden Power's type from IV parities and its pool is 17 wide,
        so a Showdown spread built for a 16-type generation lands somewhere else --
        Hidden Power Ice becomes Hidden Power Dragon on 4 of gen6ou's Zapdos/Thundurus/
        Charizard sets, which is the difference between checking Landorus and feeding it.

        Only low bits move, so every IV stays in the band its author chose (31<->30,
        0<->1) and each flip is worth one stat point at level 100. Every parity is
        reachable by flipping low bits, so a solution always exists.
        """
        if not hptype:
            return ivs, None
        rank = {stat: place for place, stat in enumerate(self.HP_FLIP_ORDER)}
        best = None
        for mask in range(64):
            candidate = [ivs[i] ^ ((mask >> i) & 1) for i in range(6)]
            if self._hp_type(candidate) != hptype:
                continue
            flipped = [i for i in range(6) if (mask >> i) & 1]
            key = (len(flipped), sum(rank[i] for i in flipped), mask)
            if best is None or key < best[0]:
                best = (key, candidate)
        if best is None:                       # unreachable; kept so it can never pass
            raise Unrepresentable(f"no IV spread yields Hidden Power {hptype}")
        assert self._hp_type(best[1]) == hptype
        # hptype is consumed here, not passed on: make_party has no field to put it in.
        return best[1], None


GAMES_BY_NAME = {"reborn": Reborn, "realidea": Realidea}
