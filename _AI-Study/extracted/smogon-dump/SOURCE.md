# Where these files come from

    https://fulllifegames.com/Tools/SmogonDump/Teams/<tier>.json    (payload)
    https://fulllifegames.com/Tools/SmogonDump/list.php             (tier index, 308 files)

FullLifeGames' **Replay Scouter** (`fulllifegames.com/Tools/ReplayScouter/#/smogonDump`,
source at github.com/FullLifeGames/replay-scouter-app) scrapes team-bearing Smogon forum
posts and serves them as one JSON file per tier. Re-fetch and convert with:

    python3 tools/fetch_smogon_dump.py --gen 7          # or: gen7ou gen7uu ...
    python3 tools/fetch_smogon_dump.py --list           # what the endpoint offers

Files here are **converted, not verbatim**: `TeamString` (Showdown export text, HTML-
escaped, sometimes carrying the post's markup) is parsed into the same schema as
`extracted/smogon-teams/`, so `showdown_names.resolve_set` reads both without changes.
The raw downloads are ~30 MB for gen 7 alone and are not vendored; `--raw-cache DIR`
keeps them if you want to re-convert without re-downloading.

## How this differs from extracted/smogon-teams/, and why it matters

| | smogon-teams/ | smogon-dump/ |
|---|---|---|
| source | Smogon's **sample team** threads | any forum post containing a team |
| curation | published by a tier maintainer | none — tournament teams and first RMTs alike |
| gen7ou size | 26 teams | 5718 (5504 of exactly six) |

The size difference is the point: sample-team scarcity is what caps the tier suite at two
disjoint sets and what let a single unbuildable Diancie delete gen6ru. The curation
difference is the cost. Every record keeps `likes`, `rmt`, `date`, `author` and `url` so a
caller can re-impose quality; **nothing in the scraper filters on them**. A draw that
ignores them samples a different population than `smogon-teams/` does, and any result
compared across the two pools has to say which it drew from.

This is also the study's only source of **whole-team co-occurrence**. `smogon_corpus.teammates()`
reads the moveset files' Teammates section, which is pairwise correlation against a usage
baseline; these are the actual six-mon lineups, so cores, item spreads and leads can be
counted instead of inferred. The Replay Scouter's own combo/item/lead statistics are
computed client-side from exactly this payload — there is no separate stats endpoint.

## What the payload actually contains

`TeamString` is not clean Showdown export, and each of these cost real teams before it
was handled. All four are covered by `tools/fetch_smogon_dump.py`:

- **The post's HTML comes with it.** `<span style="font-size: 10px">Pawniard @ Damp Rock`
  welds a tag to the species. Tags are stripped *before* unescaping, which is what makes
  it safe: the payload is HTML-escaped, so a `<` an author typed is still `&lt;` at that
  point. `<br>` becomes a newline rather than vanishing and fusing two Pokemon.
- **The blank line between Pokemon is often missing.** Splitting on blank lines turned
  every gen6monotype team into one Pokemon holding 24 moves (30 of 30 teams lost).
  Blocks are split structurally instead — a non-attribute line after an attribute line
  opens the next Pokemon — so the format survives where the whitespace does not.
- **~7% of gen 6 posts use the gen 5-era export**: `Trait:` for `Ability:`, and
  `SAtk`/`SDef`/`Spd` stat names. **`Spd` means SPEED there, while the modern `SpD` is
  special defence** — only case separates them, so the two tables are kept apart and
  selected per team by an explicit old-format probe. Merging them would silently move
  Speed EVs onto special defence.
- **The old nature line is `Adamant Nature (+Atk, -SpA)`**, which does not end in
  "Nature"; matching on a prefix instead recovered 65 gen6ou teams that were splitting
  mid-Pokemon.

**Tera type, Gigantamax and Dynamax level are preserved, not dropped.** A gen 9 set whose
`Tera Type: Ground` is discarded imports as a legal-looking team missing the thing it was
built around — the same trap `Realidea.veto` catches for Z-crystals, but invisible,
because no item gives it away. An adapter can only veto what the parser kept. **Neither
engine in this study has Terastallization and neither vetoes it yet**, so any gen 9
number must be read with that filter applied by hand (see the table below).

Records that survive all of that and still carry no move are dropped: they are
lineup-only posts (species + ability, no moves) and prose, not teams. That is ~0.5%.
`*-box` files are not teams at all — they hold 7-24 Pokemon per record — and are not
vendored.

A tier label is the *thread* the post came from, and it is not always the team's format.
This is not a curiosity, it is large and it runs in both directions:

| symptom | count | meaning |
|---|---|---|
| gen 9 pools holding a Z-crystal | **4316** | gen 9 has no Z-crystals — these are older teams |
| gen 8 pools declaring a Tera type | **3306** | gen 8 has no Tera — these are gen 9 teams |
| gen6monotype | 30 of 30 | Galarian Zapdos, Body Press, Heavy-Duty Boots |

The worst offenders are the long-running cross-generation threads: gen9doublesou (1210
Z-crystal teams), gen9pu (989), gen9monotype (954), gen9ubers (664). **Filter on content,
never on the filename.**

## Pools (fetched 2026-09-11)

`built` = teams of exactly six whose every set resolves on Realidea. `+fold` additionally
folds `X-Mega`/`X-Primal` species names to the base species, which is how forum posts
write a mega and how the sample-team pool does not; the engine mega-evolves from the
stone either way. Z-crystal holders are never filtered here — `Realidea.veto` rejects
them at resolve time.

### Gen 6 — the pool that matters for this engine

ORAS has **no Z-crystals**, which is the single mechanic Realidea lacks. That one fact is
the whole table:

| file | teams | of six | built | +fold | % |
|---|---|---|---|---|---|
| `gen6ou.json` | 4530 | 4330 | 1740 | **3162** | 73% |
| `gen6uu.json` | 761 | 745 | 348 | **601** | 81% |
| `gen6nu.json` | 493 | 485 | 386 | **397** | 82% |
| `gen6zu.json` | 404 | 402 | 288 | 288 | 72% |
| `gen6ubers.json` | 367 | 339 | 38 | 85 | 25% |
| `gen6doublesou.json` | 430 | 350 | 61 | 211 | 60% |
| `gen6ru.json` | 142 | 140 | 95 | 105 | 75% |
| `gen6lc.json` | 107 | 104 | 80 | 80 | 77% |
| `gen6anythinggoes.json` | 102 | 101 | 1 | 10 | 10% |
| `gen6pu.json` | 93 | 92 | 69 | 69 | 75% |
| `gen6cap.json` | 67 | 44 | 5 | 17 | 39% |
| `gen6monotype.json` | 30 | 30 | 0 | 0 | 0% |
| **total** | | **7162** | **3111** | **5025** | **70%** |

For scale: `extracted/smogon-teams/gen6ou.json` yields **11** eligible teams, and that
11-team pool is what caps the tier suite at two disjoint sets.

gen6ou's blockers are the same two ability mismatches `make_tier_teams.py` already
records as killing 3 of 14 sample teams, now measured at scale: Diancie's Clear Body
(80 teams) and Zapdos's Static (59) — Realidea gave those species MAGICBOUNCE and
LIGHTNINGROD instead. gen6ubers and gen6anythinggoes fail on formes this engine has no
entry for: Giratina-Origin (51) and the Arceus plate formes. gen6monotype is the
mislabelled-gen-8 file described above, not a Realidea gap.

### Gen 7 — large, but Z-crystals cost 60% of it

| file | teams | of six | built | +fold | % |
|---|---|---|---|---|---|
| `gen7ou.json` | 5735 | 5558 | 221 | 562 | 10% |
| `gen7anythinggoes.json` | 715 | 708 | 17 | 31 | 4% |
| `gen7zu.json` | 714 | 698 | 10 | 10 | 1% |
| `gen7ubers.json` | 694 | 680 | 3 | 18 | 3% |
| `gen7uu.json` | 612 | 598 | 35 | 95 | 16% |
| `gen7nu.json` | 446 | 433 | 148 | **157** | 36% |
| `gen7ru.json` | 274 | 265 | 50 | 63 | 24% |
| `gen7cap.json` | 205 | 183 | 1 | 3 | 2% |
| `gen7pu.json` | 164 | 162 | 15 | 15 | 9% |
| `gen7monotype.json` | 89 | 89 | 1 | 9 | 10% |
| `gen7nfe.json` | 63 | 63 | 11 | 11 | 17% |
| `gen7lc.json` | 44 | 44 | 14 | 14 | 32% |
| `gen7doublesou.json` | 50 | 49 | 0 | 0 | 0% |
| `gen7battlespotsingles.json` | 48 | 48 | — | — | level 50, bring-4 |
| `gen7pokebankou.json` | 14 | 14 | — | — | early-SM, superseded |
| **total** | | **9530** | **526** | **988** | **10%** |

Z-crystals alone block 3280 of gen7ou's 5558. gen7nu and gen7ru survive best because
down-tier teams lean least on the two mechanics this engine is weakest at.

### Gen 5 — small, and the one metagame that is mechanically different

907 six-mon teams from 8 files (894 singles). Small because the dump scrapes live forum
activity and the BW threads are old. `gen5doublesou` is the most contaminated file in the
whole corpus: 262 of its 288 records are four-Pokemon gen 9 VGC teams carrying
`Tera Type: ???`. 7% of gen5ou records use the gen 5-era export, the same rate as gen6ou.

Gen 5 differs from every later generation on exactly two axes, and both are the direct
fingerprint of a mechanic change rather than taste:

| | gen5 | gen6 | gen7 | gen8 | gen9 |
|---|---|---|---|---|---|
| permanent-weather ability | **0.45** | 0.19 | 0.19 | 0.20 | 0.19 |
| hazard removal per team | **0.47** | 0.71 | 0.87 | 0.79 | 0.63 |

Weather abilities were permanent in BW and became 5-turn in ORAS, so weather teams halve
after gen 5. Defog did not remove hazards until gen 6, so gen 5 has Rapid Spin and nothing
else. The corpus reproducing both discontinuities unprompted is the best end-to-end check
on the parsing that exists here.

**This has a direct consequence for the tier suite.** 11 of the 13 `gen5ou` sample teams
in `extracted/smogon-teams/` are weather teams (6 Sand Stream, 5 Drizzle) and **none of
them carries a weather rock** — in BW there was no reason to, since the ability never
expired. Realidea sets `USENEWBATTLEMECHANICS = true`, and `PokeBattle_Battler` then sets
`weatherduration = 5` (8 with the rock) instead of `-1`. So those teams get five turns of
the weather they were built around. `make_tier_teams.py` already warns that gen 5 teams
play under ORAS rules and lists Steel resistances, Knock Off and Fairy; permanent weather
is a bigger loss than any of those and is not on that list.

### Gen 8 and gen 9 — analysis pools

Fetched for cross-generation analysis rather than for either engine's tier suite. Both
are large and both are the most contaminated (above).

| gen | files | teams | of six | declaring Tera |
|---|---|---|---|---|
| gen 8 | 15 | 19918 | 18193 | 3306 (18%, all mislabelled) |
| gen 9 | 14 | 28825 | 26171 | 13444 (51%) |

Biggest: `gen8ou` 6247 six-mon, `gen8nationaldexou` 3978, `gen8nationaldex` 1559,
`gen8cap` 991; `gen9doublesou` 5959, `gen9monotype` 4467, `gen9pu` 4335, `gen9ubers`
3895, `gen9ou` 3569.

`gen9ubers` and `gen9doublesou` each drop ~1100 records as unparsed, which is genuine:
gen 9 posts increasingly show a lineup only (species + ability + Tera type, no moves),
and gen9doublesou carries index lists like `977 - Houndoom 1` that are not teams at all.

## Cross-engine buildability

Every set resolving, after folding `X-Mega`/`X-Primal` to the base species. "minus Tera"
additionally drops teams declaring a Tera type, which neither engine implements — that
column is the honest one.

| gen | six-mon | Reborn resolves | minus Tera | Realidea resolves | minus Tera |
|---|---|---|---|---|---|
| gen 6 | 7162 | 5409 | **5409 (76%)** | 5025 | **5025 (70%)** |
| gen 7 | 9592 | 5729 | **5729 (60%)** | 996 | 996 (10%) |
| gen 8 | 18193 | 12096 | **10667 (59%)** | 782 | 773 (4%) |
| gen 9 | 26171 | 13637 | 8872 (34%) | 3574 | 3521 (13%) |

Reborn is the permissive engine — it has Z-moves and the gen 8 additions — so gen 8 gives
it **10667** teams against the 11-team `gen8ou` sample pool that currently caps its suite.
Realidea's gen 9 figure looks anomalously better than its gen 7 and gen 8 ones only
because the gen 9 pools are full of mislabelled older teams; it is not a gen 9 result.

## Archetype and strategy tags

Implemented in `tools/team_tags.py`. There is no archetype field: `TeamTag` is the Smogon
*thread prefix* ("Resource", "SM OU", "Tournament"), always exactly one string per team
out of 58 values, and `TeamLineUp` is null in all 13500 records. What does carry playstyle
is `TeamTitle`, in the SPL and tournament team-dump threads:

    SPL 14 SM OU team dump/PhysKoko BO
    SPL 14 SM OU team dump/MZam hazard stack balance
    Mega Latias + Ditto Semi-Stall

Two things a single label gets wrong, both handled:

- **The title is `thread name/team description`.** Matching the whole string lets a thread
  called "...Balance Archive/..." tag every team inside it. Tags are read off the last
  "/" segment only; that alone was ~2% of labels.
- **The tags are not one axis.** "Sand Balance" is a weather *and* an archetype; "Spikes
  Stack Webs" is two modes. Archetype stays single-valued because its values nest
  (`bulky offense` ⊃ `offense`, `semi-stall` ⊃ `stall`) and the ordering resolves that.

3071 of 60969 six-mon teams carry at least one tag (5%) — densest in gen 7 (9%) and gen 8
(8%), sparse in gen 6, gen 9 and gen 5 (~2%), because naming a team by its playstyle is a
gen7/8-era tournament-thread convention.

| axis | teams | values, commonest first |
|---|---|---|
| archetype | 1990 | hyper offense 503, balance 473, bulky offense 416, stall 287, offense 262, semi-stall 49 |
| weather | 491 | sand 182, rain 147, sun 114, snow 48 |
| mode | 799 | spam 199, spikes 199, webs 160, screens 113, trick room 96, para 44, baton pass 4 |

Archetype and weather are one-per-team in practice (491 weather tags across 491 teams);
only mode ever doubles up (815 tags across 799 teams).

Not tagged, deliberately: **set descriptors** ("Specs", "Scarf", "Band", "Mega") describe
one Pokemon, and its set is already in `data`; **key mon** ("PhysKoko", "Kart", "Clef") is
an open nickname vocabulary better recovered by intersecting the title with the team's own
species list; **housekeeping** ("copy" ×1050, "Untitled", "week 3", "outdated").

**The tags were validated against the teams, not assumed.** `team_tags.agreement()` checks
a weather/mode tag against the moves and abilities the team actually runs:

| tag | tagged | confirmed | | tag | tagged | confirmed |
|---|---|---|---|---|---|---|
| spikes | 198 | **100%** | | sun | 112 | 95% |
| sand | 177 | 98% | | trick room | 94 | **100%** |
| webs | 160 | 99% | | snow | 46 | 93% |
| rain | 144 | 99% | | para | 44 | 98% |
| screens | 113 | 98% | | baton pass | 4 | 100% |

93-100% across every testable tag, so the titles are honest and the vocabulary is sound.
`spam` and every archetype carry no testable claim and are excluded from the check.

Archetype is also recoverable from composition alone — recovery/setup/hazard counts, item
classes, and offensive EV share order monotonically from stall (13% offensive EVs) through
balance (43%) to hyper offense (77%). Those features need no dex, so they classify
unbuildable and generated teams alike.

**What was learned from all this lives in `TEAM-CORPUS.md`**, at the study root: the
per-archetype role profiles, what they proved about the generated boss teams, the
readings that did not survive their null, and what the corpus does and does not feed.
This file stays provenance only.

Do not add a pool without adding its provenance here.
