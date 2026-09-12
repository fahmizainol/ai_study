#!/usr/bin/env python3
"""Multi-axis tags for a Smogon dump team, read off the post's title.

The dump has no archetype field -- `TeamTag` is the forum *thread prefix* ("Resource",
"SM OU", "Tournament"), one string per team, and it says nothing about playstyle. What
does carry playstyle is the title, because the SPL and tournament team-dump threads name
teams by what they are:

    SPL 14 SM OU team dump/PhysKoko BO
    SPL 14 SM OU team dump/DragonZ Chomp Sand Balance
    Mega Latias + Ditto Semi-Stall

Two things that a single label gets wrong, and this module does not:

**The title is `thread name/team description`.** Matching the whole string lets a thread
called "... Balance Archive/..." tag every team in it; anchoring on the last "/" segment
is what keeps a tag about the team. That alone was ~2% of labels.

**The tags are not one axis.** "Sand Balance" is a weather AND an archetype; "Spikes
Stack Webs" is two modes at once. Archetype is single-valued because its values nest
(`bulky offense` contains `offense`, `semi-stall` contains `stall`) and the ordering
resolves that; weather and mode are genuinely multi-valued.

Deliberately NOT tagged here:

  set descriptors  "Specs", "Scarf", "Band", "Sub", "Mega" -- these describe one
                   Pokemon's set, not the team, and the set itself is already in `data`.
  key mon          "PhysKoko", "Kart", "Clef" -- an open vocabulary of nicknames. These
                   are better recovered by intersecting the title against the team's own
                   species list than by any dictionary.
  housekeeping     "copy", "Untitled 12", "week 3", "outdated" -- not tags at all.

A tag is a claim about the team made by its author, so it is evidence, not ground truth:
titles are free text, abbreviations collide (`TR`, `BO`, `HO`), and most teams carry no
title at all. `agreement()` exists to keep that honest -- it checks a mode tag against
the moves the team actually runs.
"""

import re

# Ordered: a value that contains another must be tried first. Single-valued.
ARCHETYPE = [
    ("semi-stall",    r"semi[\s-]?stall"),
    ("stall",         r"\bstall\b"),
    ("hyper offense", r"hyper[\s-]?offen[sc]e|\bHO\b"),
    ("bulky offense", r"bulky[\s-]?offen[sc]e|\bBO\b"),
    ("balance",       r"\bbalanced?\b"),
    ("offense",       r"\boffen[sc]e|\boffensive\b"),
]

# Multi-valued. Weather and mode are independent of archetype and of each other.
WEATHER = [
    ("rain", r"\brain\b"),
    ("sun",  r"\bsun\b"),
    ("sand", r"\bsand\b"),
    ("snow", r"\bhail\b|\bsnow\b"),
]
MODE = [
    ("webs",        r"\bwebs?\b|sticky[\s-]?web"),
    ("screens",     r"\bscreens?\b|aurora[\s-]?veil|dual[\s-]?screen"),
    ("spikes",      r"\bspikes?\b|hazard[\s-]?stack|spike[\s-]?stack"),
    ("trick room",  r"\btrick[\s-]?room\b|\bTR\b"),
    ("baton pass",  r"\bbaton[\s-]?pass\b"),
    ("para",        r"\bpara[\s-]?spam\b|\bparalysis\b"),
    ("spam",        r"\bspam\b"),
]

# Stripped before matching: none of it describes a team.
NOISE = re.compile(r"\bcopy\b|\buntitled\s*\d*\b|\bweek\s*\d+\b|\boutdated\b"
                   r"|\bsample\b|\bexperiment\b|\bv\d+\b", re.I)

# What a mode tag implies the team should actually run, for agreement().
MODE_MOVES = {
    "webs":       {"STICKYWEB"},
    "screens":    {"REFLECT", "LIGHTSCREEN", "AURORAVEIL"},
    "spikes":     {"SPIKES", "TOXICSPIKES", "STEALTHROCK"},
    "trick room": {"TRICKROOM"},
    "baton pass": {"BATONPASS"},
    "para":       {"THUNDERWAVE", "GLARE", "STUNSPORE", "NUZZLE"},
}
WEATHER_MOVES = {
    "rain": {"RAINDANCE"}, "sun": {"SUNNYDAY"},
    "sand": {"SANDSTORM"}, "snow": {"HAIL", "SNOWSCAPE", "CHILLYRECEPTION"},
}
WEATHER_ABILITY = {
    "rain": {"DRIZZLE"}, "sun": {"DROUGHT", "ORICHALCUMPULSE"},
    "sand": {"SANDSTREAM", "SANDSPIT"}, "snow": {"SNOWWARNING"},
}


def norm(s):
    return re.sub(r"[^A-Z0-9]", "", (s or "").upper())


def description(title):
    """The team's own half of `thread name/team description`."""
    return NOISE.sub(" ", (title or "").rsplit("/", 1)[-1]).strip()


def tags(title):
    """-> {"archetype": str|None, "weather": [...], "mode": [...]}."""
    text = description(title)
    archetype = next((k for k, p in ARCHETYPE if re.search(p, text, re.I)), None)
    return {
        "archetype": archetype,
        "weather": [k for k, p in WEATHER if re.search(p, text, re.I)],
        "mode": [k for k, p in MODE if re.search(p, text, re.I)],
    }


def agreement(tag, team):
    """Does the team actually run what a weather/mode tag claims? -> True/False/None.

    None means the tag carries no testable claim (every archetype, and `spam`). This is
    the only check on a vocabulary scraped from free text, so it is worth running before
    trusting any of it.
    """
    moves = {norm(m) for s in team for m in s.get("moves", [])}
    if tag in MODE_MOVES:
        return bool(moves & MODE_MOVES[tag])
    if tag in WEATHER_MOVES:
        abilities = {norm(s.get("ability")) for s in team}
        return bool(moves & WEATHER_MOVES[tag] or abilities & WEATHER_ABILITY[tag])
    return None
