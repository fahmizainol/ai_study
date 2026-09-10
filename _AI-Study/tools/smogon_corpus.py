#!/usr/bin/env python3
"""Smogon corpora used by the boss-team generator: tiers, published sets, and
teammate correlation.

Three vendored sources under extracted/, each with a MANIFEST beside it:

  smogon-formats/  gen7-formats-data.ts   -> tier(species)
  smogon-sets/     gen{6,7,8,9}.json      -> sets(species)
  smogon-stats/    gen7*.txt              -> teammates(species)

Nothing here knows about Realidea. Species are keyed by `norm()` (uppercase
alphanumerics) so Showdown's "Landorus-Therian" and PBS's "LANDORUSTHERIAN" meet in
the middle; callers resolve back to their own names.

`dex` sets are Smogon-copyrighted (see extracted/smogon-sets-MANIFEST.txt). Call
stats_only() before the first sets() to drop them from every subsequent load.
"""
import collections
import json
import os
import re
from functools import lru_cache

HERE = os.path.dirname(os.path.abspath(__file__))
EXTRACTED = os.path.join(HERE, "..", "extracted")

_STATS_ONLY = False


def stats_only(on=True):
    """Drop Smogon's copyrighted `dex` sets, keeping only MIT-licensed `stats` sets.
    Required for any build that leaves this machine. Must be called before sets()."""
    global _STATS_ONLY
    _STATS_ONLY = on
    sets.cache_clear()


def norm(s):
    return re.sub(r"[^A-Z0-9]", "", (s or "").upper())


# ---------------------------------------------------------------- tiers
# Showdown's own ordering, strongest first. The BL tiers sit directly above the tier
# they are banned from, which is what "banlist" means: UUBL is too strong for UU.
RANK = ["Uber", "OU", "(OU)", "UUBL", "UU", "RUBL", "RU", "NUBL", "NU",
        "PUBL", "PU", "ZUBL", "ZU", "NFE", "LC"]

# BL tiers collapse into the tier above them for mix-scheduling; everything at PU or
# below is one "low" bucket, since the generator never distinguishes them.
BAND = {"Uber": "Uber", "OU": "OU", "(OU)": "OU", "UUBL": "UU", "UU": "UU",
        "RUBL": "RU", "RU": "RU", "NUBL": "NU", "NU": "NU", "PUBL": "low",
        "PU": "low", "ZUBL": "low", "ZU": "low", "NFE": "low", "LC": "low"}
BANDS = ["Uber", "OU", "UU", "RU", "NU", "low"]


@lru_cache(maxsize=1)
def tiers():
    """{NORMALIZEDNAME: tier string}. Uses gen 7 — Realidea's own generation."""
    path = os.path.join(EXTRACTED, "smogon-formats", "gen7-formats-data.ts")
    out = {}
    for m in re.finditer(r"(\w+):\s*\{([^}]*)\}", open(path, encoding="utf-8").read()):
        t = re.search(r'tier:\s*"([^"]+)"', m.group(2))
        if t:
            out[re.sub(r"[^a-z0-9]", "", m.group(1).lower())] = t.group(1)
    return out


def tier(name):
    return tiers().get(norm(name).lower(), "?")


def rank(name):
    """Index into RANK — lower is stronger. Unknown species sort last."""
    t = tier(name)
    return RANK.index(t) if t in RANK else len(RANK)


def band(name):
    return BAND.get(tier(name), "low")


# ---------------------------------------------------------------- sets
# Formats whose mechanics this engine does not have, or whose rules make their sets
# meaningless as "what a strong trainer would bring".
_SKIP_FORMAT = ("1v1", "letsgoou", "purehackmons", "balancedhackmons",
                "almostanyability", "cap")
# From gen 8/9 files, only these formats — they cover gen-7-legal mons that gen 7's
# own tiers miss. Their native formats assume Dynamax/Tera and are skipped.
_CROSSGEN_OK = ("nationaldex", "ubers", "anythinggoes")


@lru_cache(maxsize=1)
def sets():
    """{NORMALIZEDNAME: {(format, source, setname): set dict}}.

    `source` is "dex" or "stats"; see the module docstring on licensing."""
    pool = collections.defaultdict(dict)
    sources = ("stats",) if _STATS_ONLY else ("dex", "stats")
    for fname in ("gen6.json", "gen7.json", "gen8.json", "gen9.json"):
        path = os.path.join(EXTRACTED, "smogon-sets", fname)
        for fmt, formats in json.load(open(path, encoding="utf-8")).items():
            if any(b in fmt for b in _SKIP_FORMAT):
                continue
            if fname in ("gen8.json", "gen9.json") and not any(k in fmt for k in _CROSSGEN_OK):
                continue
            for source in sources:
                for species, named in formats.get(source, {}).items():
                    for setname, st in named.items():
                        pool[norm(species)][(fmt, source, setname)] = st
    return pool


# ---------------------------------------------------------------- usage stats
_SECTIONS = {"Abilities", "Items", "Spreads", "Moves", "Teammates",
             "Checks and Counters"}


def _parse_moveset_file(path):
    """One Smogon moveset .txt -> {species name: {section: [(name, value)...]}}.

    The format has no species delimiter: a name line is simply the line before
    "Raw count:", so the parser carries the previous non-border line forward."""
    out, cur, section, prev = {}, None, None, None
    for line in open(path, encoding="utf-8", errors="replace"):
        s = line.rstrip("\n").strip()
        if s and set(s) <= set("+- "):        # box-drawing border
            continue
        if s.startswith("|"):
            s = s.strip("|").strip()
        if not s:
            continue
        if s.startswith("Raw count"):
            cur = {"name": prev, "raw": int(re.search(r"(\d+)", s).group(1)),
                   **{k: [] for k in _SECTIONS}}
            out[prev] = cur
            section = None
            continue
        if s in _SECTIONS:
            section = s
            continue
        if cur and s.startswith("Viability Ceiling"):
            cur["viability"] = int(re.search(r"(\d+)", s).group(1))
            continue
        if s.startswith("Avg. weight"):
            continue
        if cur and section:
            # every section but Checks and Counters is "<name>  <pct>%"
            m = re.match(r"^(.*?)\s+([+\-]?[\d.]+)%$", s)
            if m and section != "Checks and Counters":
                cur[section].append((m.group(1).strip(), float(m.group(2))))
                continue
            c = re.match(r"^(.*?)\s+([\d.]+)\s+\(", s)
            if c and section == "Checks and Counters":
                cur[section].append((c.group(1).strip(), float(c.group(2))))
                continue
        # not consumed by any section -> candidate species name for the next entry
        prev = s
    return out


@lru_cache(maxsize=1)
def usage():
    """{NORMALIZEDNAME: {format: entry}} merged across the six vendored gen-7 tiers."""
    out = collections.defaultdict(dict)
    d = os.path.join(EXTRACTED, "smogon-stats")
    for fname in sorted(os.listdir(d)):
        if not fname.endswith(".txt"):
            continue
        for name, entry in _parse_moveset_file(os.path.join(d, fname)).items():
            out[norm(name)][fname[:-4]] = entry
    return out


@lru_cache(maxsize=None)
def teammates(name):
    """{NORMALIZEDNAME: best co-occurrence %} for one species, across all tiers.

    Max rather than sum: a mon that appears in three tiers should not out-score an
    equally-correlated partner that only appears in one."""
    out = collections.Counter()
    for entry in usage().get(norm(name), {}).values():
        for mate, pct in entry["Teammates"]:
            out[norm(mate)] = max(out[norm(mate)], pct)
    return out


if __name__ == "__main__":
    print(f"tiers    : {len(tiers())} species")
    print(f"sets     : {len(sets())} species, "
          f"{sum(len(v) for v in sets().values())} sets"
          f"{' (stats only)' if _STATS_ONLY else ''}")
    print(f"usage    : {len(usage())} species")
    counts = collections.Counter(band(n) for n in tiers())
    print("bands    : " + "  ".join(f"{b}:{counts[b]}" for b in BANDS))
