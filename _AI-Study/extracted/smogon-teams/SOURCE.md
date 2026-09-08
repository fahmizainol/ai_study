# Where these files come from

    https://pkmn.github.io/smogon/data/teams/<tier>.json

One file per tier, fetched verbatim and vendored unchanged. Re-fetch with:

    curl -sS -o extracted/smogon-teams/<tier>.json \
         https://pkmn.github.io/smogon/data/teams/<tier>.json

This is the `pkmn/smogon` mirror of Smogon's per-tier **sample team** threads — teams a
person built and a tier maintainer published, which is the whole premise of the tier
suite (see `tools/make_tier_teams.py`). It is not the `data/sets/` endpoint on the same
host: that one carries per-species analysis sets, which would give the suite six
Pokemon that never met each other.

Vendored rather than fetched at build time so generation stays offline and reproducible,
like the rest of the study's validation. The four original files were verified
byte-identical to this endpoint on 2026-09-07, which is how the URL was recovered — it
had been left out of the commit that added them, and nothing in the repo recorded it.
Do not add a pool without adding its provenance here.

## Pools

| file | teams | used for |
|---|---|---|
| `gen6ou.json` | 14 | Reborn + Realidea (`gen6ou_a`, `gen6ou_b`) |
| `gen6uu.json` | 4 | Realidea (`gen6uu_a`) |
| `gen6ru.json` | 5 | **nothing** — see below |
| `gen5ou.json` | 13 | Realidea (`gen5ou_a`, `gen5ou_b`) |
| `gen5uu.json` | 9 | Realidea (`gen5uu_a`, `gen5uu_b`) |
| `gen5ru.json` | 4 | Realidea (`gen5ru_a`) |
| `gen7ou.json` | 26 | Reborn only (Realidea has no Z-move engine) |
| `gen8ou.json` | 11 | Reborn |
| `gen8uu.json` | 24 | Reborn |

`gen6ru.json` is kept although nothing draws from it: 3 of its 5 teams are unbuildable on
Realidea's v16 dex (two want Clear Body on a Diancie this engine gave `Abilities=MAGICBOUNCE`
and nothing else, one wants a Glalitite it does not have), and 2 teams cannot fill a
4-team set. It becomes usable the moment either gap closes, and keeping the file is what
records that the tier was tried rather than overlooked.
