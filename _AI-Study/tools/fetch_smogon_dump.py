#!/usr/bin/env python3
"""Fetch Smogon team dumps from FullLifeGames' Replay Scouter and convert them to
the sample-team schema this study already reads.

Why a second team source. extracted/smogon-teams/ holds Smogon's *sample* teams --
maintainer-vetted, one thread per tier, and tiny: 26 teams for gen7ou, 4 for gen5ru.
That ceiling is what caps the tier suite at two disjoint sets and what makes a single
unbuildable species (gen6ru's Diancie) delete a whole tier. This source is the Replay
Scouter's dump of team-bearing Smogon forum posts -- tournament threads and RMTs --
which is roughly 200x larger and turns "which four teams can we build" into a sampling
problem instead of a scarcity one.

That size is bought with provenance, and the two pools must not be confused:

  smogon-teams/  sample threads      curated, published as representative of the tier
  smogon-dump/   scraped forum posts uncurated -- a tournament team and someone's first
                 RMT sit side by side, and only the post's metadata separates them

So every record here keeps the signals that let a caller re-impose quality: `likes` (the
post's like count), `rmt` (whether it came from a Rate My Team thread), `date`, `author`
and `url`. Nothing in this file filters on them -- that is the generator's call, not the
scraper's -- but a draw that ignores them is drawing from a different population than
extracted/smogon-teams/, and any comparison across the two has to say so.

The dump is also the only source of whole-team co-occurrence we have. smogon_corpus's
teammates() comes from the moveset files' Teammates section, which is pairwise
correlation against a usage baseline; these are the actual six-mon lineups, so item
spreads, leads and n-way cores can be counted directly rather than inferred. The Replay
Scouter computes exactly those statistics client-side from this same payload.

Output is the schema of extracted/smogon-teams/<tier>.json -- [{name, author, data:
[set, ...]}, ...] -- so showdown_names.resolve_set and make_tier_teams.eligible_teams
consume it with no changes. Species that an engine cannot build (Realidea's Z-crystal
veto foremost) are NOT filtered here; they surface as Unrepresentable at resolve time,
where the reason is recorded.

Usage:
    python3 fetch_smogon_dump.py --list                    # tiers the endpoint offers
    python3 fetch_smogon_dump.py gen7ou gen7uu             # fetch, convert, vendor
    python3 fetch_smogon_dump.py --gen 7                   # every gen 7 tier it has
    python3 fetch_smogon_dump.py gen7ou --raw-cache DIR    # reuse/keep raw downloads
"""

import argparse
import collections
import html
import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

STUDY = Path(__file__).resolve().parents[1]
OUT = STUDY / "extracted" / "smogon-dump"

BASE = "https://fulllifegames.com/Tools/SmogonDump"
LIST_URL = f"{BASE}/list.php"
TEAMS_URL = f"{BASE}/Teams/{{}}.json"

# Showdown's export stat labels -> the keys resolve_set indexes by.
STAT_KEYS = {"HP": "hp", "Atk": "atk", "Def": "def",
             "SpA": "spa", "SpD": "spd", "Spe": "spe"}

# The gen 5-era export, still ~7% of the gen 6 pools. It is not merely older spelling:
# `Spd` means SPEED here, while in the modern format the same letters (`SpD`) mean
# special defence. Only case separates them, so the two tables must never be merged --
# an old-format team read with the modern one lands its Speed EVs on special defence.
OLD_STAT_KEYS = {**STAT_KEYS, "SAtk": "spa", "SDef": "spd", "Spd": "spe"}
OLD_FORMAT_RE = re.compile(r"^\s*Trait:|\b\d+\s+(?:SAtk|SDef)\b", re.M)

STAT_RE = {False: re.compile(r"(\d+)\s+(%s)\b" % "|".join(STAT_KEYS)),
           True: re.compile(r"(\d+)\s+(%s)\b" % "|".join(OLD_STAT_KEYS))}

# "Adamant Nature" and the old "Adamant Nature (+Atk, -SpA)" alike.
NATURE_RE = re.compile(r"^([A-Za-z]+)\s+Nature\b")

# "Nickname (Species) (M) @ Item". Item is split on " @ " rather than "@" because a
# nickname may contain an @ and an item never does.
GENDER_RE = re.compile(r"\s*\((M|F)\)\s*$")

# The dump's own scraper sometimes strips an opening tag but leaves its attributes, so
# a "header" can arrive as bare `data-src="https://..." data-lb-sidebar-href=""`. There
# is no tag left for strip_markup to catch, so the species itself has to be checked: a
# real one is short and holds no quote, equals sign, slash, angle bracket or URL.
_NOT_SPECIES = re.compile(r'["=<>/\\]|https?:', re.I)


def IS_SPECIES(name):
    return len(name) <= 40 and not _NOT_SPECIES.search(name)
NICK_RE = re.compile(r"^(?P<nick>.*\S)\s+\((?P<species>[^()]+)\)$")


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def list_tiers():
    return [n[:-5] for n in get(LIST_URL) if n.endswith(".json")]


def strip_markup(text):
    """Forum HTML -> plain export text.

    The dump carries the post's markup, so a team can arrive as
    `<span style="font-size: 10px">Pawniard @ Damp Rock` -- the tag is glued to the
    species and costs the whole team. Tags are stripped BEFORE unescaping, which is
    what makes this safe: the payload is HTML-escaped, so a literal `<` an author
    typed is still `&lt;` at this point and cannot be mistaken for a tag. `<br>` is a
    line break in HTML and a block separator here, so it becomes a newline rather
    than vanishing and welding two Pokemon together.
    """
    text = (text or "").replace("\r\n", "\n")
    text = re.sub(r"<\s*br\s*/?\s*>", "\n", text, flags=re.I)
    text = re.sub(r"</?\s*(?:p|div|li|tr)\b[^>]*>", "\n", text, flags=re.I)
    text = re.sub(r"</?[a-zA-Z][^>]*>", "", text)
    return html.unescape(text)


def parse_pokemon(block, old_format=False):
    """One export block -> a set dict, or None if the block is not a Pokemon.

    The dump scrapes whole forum posts, so a "block" is often prose that happened to
    sit between two blank lines. Requiring a move is what separates the two: every
    real export has at least one "- Move" line and no paragraph of English does.
    """
    lines = [ln.strip() for ln in block.strip().splitlines() if ln.strip()]
    if not lines:
        return None

    head, rest = lines[0], lines[1:]
    item = None
    if " @ " in head:
        head, item = head.rsplit(" @ ", 1)
        item = item.strip() or None

    gender = None
    g = GENDER_RE.search(head)
    if g:
        gender, head = g.group(1), head[:g.start()]
    nick = NICK_RE.match(head.strip())
    species = (nick.group("species") if nick else head).strip()
    if not species or not IS_SPECIES(species):
        return None

    out = {"species": species}
    if gender:
        out["gender"] = gender
    if item:
        out["item"] = item

    moves = []
    for line in rest:
        if line.startswith("-"):
            move = line[1:].strip()
            if move:
                moves.append(move)
        elif line.startswith(("Ability:", "Trait:")):
            out["ability"] = line.split(":", 1)[1].strip()
        # Mechanics this study's engines do not have. They are kept, not dropped: a
        # set that silently loses its Tera type imports as a legal-looking team that
        # is missing the thing it was built around -- the same trap Realidea.veto
        # catches for Z-crystals, but invisible, because no item gives it away. An
        # adapter can only veto what the parser preserved.
        elif line.startswith("Tera Type:"):
            out["teraType"] = line.split(":", 1)[1].strip()
        elif line.startswith("Gigantamax:"):
            out["gigantamax"] = line.split(":", 1)[1].strip().lower() == "yes"
        elif line.startswith("Dynamax Level:"):
            out["dynamaxLevel"] = int(re.search(r"\d+", line).group())
        elif line.startswith("Level:"):
            level = re.search(r"\d+", line)
            if level and int(level.group()) != 100:
                out["level"] = int(level.group())
        elif line.startswith(("EVs:", "IVs:")):
            key = "evs" if line.startswith("EVs:") else "ivs"
            table = OLD_STAT_KEYS if old_format else STAT_KEYS
            spread = {}
            for value, stat in STAT_RE[old_format].findall(line.split(":", 1)[1]):
                spread[table[stat]] = int(value)
            if spread:
                out[key] = spread
        else:
            nature = NATURE_RE.match(line)
            if nature:
                out["nature"] = nature.group(1)

    if not moves:
        return None
    out["moves"] = moves
    return out


# Every line of an export block except the header: "- Move", "Ability: X", "EVs: ...",
# "Timid Nature", and the handful of optional flags.
ATTR_PREFIX = ("ability:", "trait:", "level:", "shiny:", "happiness:", "evs:", "ivs:",
               "tera type:", "dynamax level:", "gigantamax:", "nature:")


def is_attribute(line):
    # `endswith` as well as the prefix match, because a post may offer a choice:
    # "Jolly / Adamant Nature" starts with neither a nature nor a known prefix, and
    # without this it reads as the next Pokemon's header and splits the set in two.
    return (line.startswith("-") or line.lower().startswith(ATTR_PREFIX)
            or NATURE_RE.match(line) is not None
            or line.lower().endswith("nature"))


def split_blocks(text):
    """Export text -> [[line, ...], ...], one list per Pokemon.

    Splitting on blank lines is the obvious reading of the format and it is wrong
    here: forum posts routinely lose the blank line between Pokemon, and every such
    team then parses as one Pokemon holding 24 moves. The structure survives where
    the whitespace does not -- a block is a header line followed by attribute lines,
    so any non-attribute line arriving after an attribute line opens the next
    Pokemon. Blank lines stop carrying meaning at all, which is why prose posts
    still collapse to move-less blocks and get dropped downstream.
    """
    blocks, current = [], []
    for raw in text.split("\n"):
        line = raw.strip()
        if not line:
            continue
        if not is_attribute(line) and any(is_attribute(x) for x in current):
            blocks.append(current)
            current = [line]
        else:
            current.append(line)
    if current:
        blocks.append(current)
    return blocks


def parse_team_string(text):
    """Showdown export text -> [set, ...]. Blocks that are not Pokemon are dropped."""
    text = strip_markup(text)
    old = OLD_FORMAT_RE.search(text) is not None
    mons = []
    for block in split_blocks(text):
        mon = parse_pokemon("\n".join(block), old)
        if mon:
            mons.append(mon)
    return mons


def convert(records):
    """Dump records -> sample-team schema, deduplicated. Returns (teams, stats)."""
    stats = collections.Counter()
    seen, teams = set(), []
    for record in records:
        stats["records"] += 1
        key = record.get("RegexTeam") or record.get("TeamString")
        if not key or key in seen:
            stats["duplicate"] += 1
            continue
        seen.add(key)
        mons = parse_team_string(record.get("TeamString"))
        if not mons:
            stats["unparsed"] += 1
            continue
        # A post can hold several teams, or a fragment of one. Six is a full team; the
        # rest are kept with their real size and left for the caller to filter, because
        # "5 mons" is sometimes a genuine team and sometimes a truncated quote.
        if len(mons) > 6:
            stats["oversized"] += 1
        stats[f"size{min(len(mons), 7)}"] += 1
        teams.append({
            "name": record.get("TeamTitle") or record.get("TeamTag") or "",
            "author": record.get("PostedBy") or "",
            "url": record.get("URL") or "",
            "date": record.get("PostDate") or "",
            "likes": record.get("Likes") or 0,
            "rmt": bool(record.get("RMT")),
            "data": mons,
        })
        stats["teams"] += 1
    return teams, stats


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tiers", nargs="*", help="tier ids, e.g. gen7ou")
    ap.add_argument("--list", action="store_true", help="print available tiers and exit")
    ap.add_argument("--gen", help="fetch every tier whose id starts with gen<N>")
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--raw-cache", type=Path,
                    help="directory of raw downloads; reused when present, written when not")
    args = ap.parse_args()

    available = list_tiers()
    if args.list:
        for tier in available:
            print(tier)
        return 0

    wanted = list(args.tiers)
    if args.gen:
        wanted += [t for t in available if t.startswith(f"gen{args.gen}")]
    if not wanted:
        ap.error("name at least one tier, or pass --gen N / --list")

    missing = [t for t in wanted if t not in available]
    if missing:
        return f"not offered by the endpoint: {', '.join(missing)}"

    args.out.mkdir(parents=True, exist_ok=True)
    for tier in dict.fromkeys(wanted):
        cached = args.raw_cache / f"{tier}.json" if args.raw_cache else None
        if cached and cached.exists():
            records = json.loads(cached.read_text(encoding="utf-8"))
        else:
            records = get(TEAMS_URL.format(urllib.parse.quote(tier)))
            if cached:
                cached.parent.mkdir(parents=True, exist_ok=True)
                cached.write_text(json.dumps(records), encoding="utf-8")
        teams, stats = convert(records)
        (args.out / f"{tier}.json").write_text(
            json.dumps(teams, separators=(",", ":")), encoding="utf-8")
        full = stats["size6"]
        print(f"{tier:<22} {stats['records']:>6} records  {stats['teams']:>6} teams  "
              f"{full:>6} of six  {stats['duplicate']:>6} dup  "
              f"{stats['unparsed']:>5} unparsed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
