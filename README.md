# Portable Battle AI for Pokémon Fangames

**Goal: one battle AI good enough to be worth installing, and portable enough to drop
into any Essentials fangame without rewriting it for each one.**

Fangame difficulty is mostly bolted on — level spikes, cheat items, and AI that reads
your move choice. The interesting question is whether a *fair* AI can be strong instead,
and whether it can be written once and shipped everywhere. This repo is the attempt, plus
the teardown of ten existing fangame AIs that it learns from.

The design that makes "everywhere" possible is a hard split:

| | |
|---|---|
| **Core** (`_AI-Study/portable_ai/`) | Pure decision logic. Scores moves and switches from a plain data snapshot. **Makes no engine calls at all** — it does not know what game it is running in. |
| **Adapter** (`_AI-Study/adapters/<game>/`) | ~1 file per game. Builds that snapshot out of the host engine, and is the *only* code allowed to touch it. |

Install is opt-in and reversible: drop in one generated script file, create a marker file
to turn it on, delete the marker to get the game's own AI back. Nothing else in the game
is modified. It is currently installed in two games whose engines are five Essentials
versions apart, running the same core.

---

## 1. Where it stands

| | status |
|---|---|
| **Portable core** | **v0.6.2** — the real development line |
| **Reborn Yang adapter** | Installed, corpus-validated, benchmarked every version. This is where all the work happens. |
| **Realidea V4.1 adapter** | Installed but **stranded at core v0.1.0**. It works; it just has not been rebuilt since Sept 4. Its adapter also doesn't export the newer facts the core has learned to use, so those rules would sit inert until it does. |
| **Games torn down** | 10 Essentials games (v16 → v21) + 1 GBA/CFRU hack |

### Latest benchmark

The AI plays Reborn Yang's own engine against a fixed schedule of 6v6 battles — 7 team
rosters × 60 battles = **420 battles per version**, same teams, same seeds, every time.

| version | wins / 420 | | vs previous |
|---|---:|---:|---|
| 0.6.0 | 197 | 46.9% | — |
| 0.6.1 | 205 | 48.8% | **+8** (p = 0.043) — Leech Seed applicability |
| **0.6.2** | **203** | **48.3%** | −2 (p = 0.83) — seven bug fixes, flat on wins |

**How to read that.** The schedule is symmetric, so Reborn's own AI playing *itself* has
to land near 50% — and measures 52.7%. So ~50% is the bar, and the portable AI sits a
couple of points under it: **close to Reborn's AI, not yet past it.** Reborn's AI is
17,600 lines of per-move and per-ability special cases; the portable core is a few
thousand lines of general rules, so "nearly as good" is already the interesting result.

Two findings worth more than the win column:

- **Reborn's "Intense" cheat mode buys it nothing** — cheating costs it 7 battles against
  its own Normal AI (p = 0.54). The same cheats take **23 battles off the portable AI**
  (p = 0.017), because the cheats read your intent and the portable AI is more predictable.
  Being readable is a real weakness; being able to read is not much of a strength.
- **v0.6.2 changed the course of 30% of battles and won nothing.** Seven genuine bugs,
  fixed and verified, net −2 wins. Correctness and strength are not the same axis, and
  this project reports them separately.

---

## 2. How to work on this

Two independent workstreams. Full detail in
[`_AI-Study/README.md`](_AI-Study/README.md); this is the shape of each.

### A. Make the AI stronger

The method that has actually produced results is **reading battles, not reading code.**
Every one of the seven fixes in v0.6.2 was found by rendering a real battle turn by turn
and watching the AI do something stupid. Fixes proposed by staring at the source instead
have a poor track record here.

The loop:

1. **Find a misplay.** Render traced battles to text (`tools/render_battle.py`) and read
   them. Both AIs are traced in the same run, so the stock-Reborn line is right there for
   comparison — when it plays the position better, read *its* code for that case and see
   what rule you're missing.
2. **Fix it in the core**, behind its own on/off key so it can be turned off later.
3. **Unit tests** — seconds, run constantly.
4. **Version bump. Now the required checks, in order:**
   - **The scenario corpus** — 213 hand-built positions with assertions about what a
     good AI must do there (`tools/check_scenarios.py`). Every new rule ships with a card
     that *fails on the previous version* — a card that passes on both proves nothing.
   - **The control run** — the new build with your new keys switched off must reproduce
     the previous version **battle for battle**. Not the same win total; the same battles.
     Nothing below this is meaningful without it.
   - **The simulation** — all 420 battles, 4 parallel workers, then a paired comparison
     against the previous version (`tools/compare_versions.py`).
5. **Write it up** in `PORTABLE-AI-REBORN.md`, including what didn't work.

Two rules learned the hard way, both from real retractions in the log: **one roster is
not a measurement** (60 battles cannot see an effect this size — v0.6.2 looked like a
gain on one roster and was a small loss over all seven), and **ship rules in batches**,
because a single rule has never moved the win count detectably.

### B. Build competitive teams

A strong AI handed a bad team is still a pushover, and Realidea's teams are the weakest
input in the study: 178 battles, 406 Pokémon, **zero EVs, random IVs, 7% held items, no
custom movesets**. Spec and stage tables are in
[`TEAM-DESIGN.md`](_AI-Study/TEAM-DESIGN.md). Two tiers, because they need different
tools:

- **Filler teams — generated, ~134 done.** Every ordinary trainer, rebuilt by script
  (`tools/generate_filler.py`). It **keeps the developer's own species** and just
  re-equips them for their point in the game — moves, item, ability, nature, IVs, EV
  budget — from a per-gym knob schedule. New Pokémon are only invented to fill slots when
  a party is supposed to grow. Seeded, so it reproduces exactly, and every team goes
  through a legality validator (`tools/validate_team.py`) that checks the move is actually
  learnable at that level, the evolution is actually reachable, and so on.
- **Boss teams — hand/LLM-designed, ~31 to go.** Gym leaders and rivals need synergy a
  generator can't fake: a lead that sets up, a wall that answers your starter, a cleaner.
  These are written against a rubric, then run through the same validator. **1 deployed**
  (gym 1), 3 drafted. Targets Reborn-Intense's curve — 6 Pokémon from gym 1, full EVs,
  31 IVs — and assumes the improved AI will be there to pilot them.

---

## 3. Recommendation — what I'd do next

**1. Prove the "portable" claim before polishing the AI further.** This is the headline
goal and it is the least tested thing in the repo. Everything since v0.2.0 has been
designed, tuned and measured against exactly one engine. The core is *structurally*
portable — no engine calls — but nothing currently checks that it hasn't quietly grown
Reborn-shaped assumptions. Rebuilding the stranded Realidea adapter to v0.6.2 would test
that in a day, and a third adapter (Hegemony or Ashen Frost — both already torn down,
both a different Essentials era) would settle it. A core that ships to three engines at
48% is a better result than one that ships to one engine at 52%.

**2. Then go after the scoring model, not more special cases.** The last three versions
moved +8, −2, and the fix list is thinning. The structural gap is known and written down:
Reborn scores a move as a *percentage of the target's current HP* — so a 2HKO and a 3HKO
are genuinely different — while the portable core gives a kill a flat bonus and flattens
everything below it. A hits-to-KO ladder settled in move order (including priority moves)
is the single change most likely to move the win column, the helper for it already exists
from v0.6.0, and the scoring rules still don't consult it.

**3. Cheap and owed: ablate v0.6.2.** Seven fixes shipped together for −2 wins, so none of
them can be blamed or cleared. Seven runs of the existing frame (~35 minutes) would say
whether one is quietly costing battles while the rest pay for it — the prime suspect is
already named in the log.

**4. Don't chase statistical significance per version.** At 420 battles the frame can only
detect fairly large effects, and most correct changes are smaller than that. Keep reporting
behaviour ("2HKOed-and-slower setups: 3 → 0") alongside wins, as the log has started doing.
It's the honest measurement and it's the one that shows the AI improving.

---

## Requirements

Deliberately close to nothing — the study should run on a clean machine.

| | | |
|---|---|---|
| **Python 3** | 3.12 here, 3.8+ is fine | **Standard library only.** Every tool in `tools/` imports nothing but stdlib plus its own siblings, so there is no `requirements.txt` to install — that is the intended state, not an oversight. |
| **Ruby** | 3.2 here | Runs the unit tests and the `ruby -c` syntax check in the build step. Only the *tests* need a gem: `test/unit`, bundled with Ruby 3.x already, otherwise `gem install test-unit`. |
| **The games** | — | Not in this repo, and nothing that touches a real battle works without them. |
| **Windows** | — | Only for running battles. `Game.exe` is a Windows process (~250 MB each); WSL just orchestrates it, so the parallel worker count is capped by Windows free RAM, not by CPU count. |

Two Rubies are in play and they are not interchangeable: the system Ruby above runs the
tests, while the AI itself executes inside each game's own interpreter — mkxp-z (modern
Ruby) for Reborn, RGSS 1.8-era for Realidea. Code written for one will not always parse in
the other, which is why the core is plain, conservative Ruby.

## Repo layout

Everything lives in [`_AI-Study/`](_AI-Study/). Start with its
[README](_AI-Study/README.md) — status, the full workflow, and the traps.

| doc | what |
|---|---|
| [`ANALYSIS.md`](_AI-Study/ANALYSIS.md) | The teardown: what each of the ten games' AI actually does, with file:line citations |
| [`AI-PORTABILITY.md`](_AI-Study/AI-PORTABILITY.md) | Engine census (v16 → v21) and the core/adapter contract |
| [`SIM-SPEC.md`](_AI-Study/SIM-SPEC.md) | How an AI's decisions get measured instead of eyeballed |
| [`PORTABLE-AI-REBORN.md`](_AI-Study/PORTABLE-AI-REBORN.md) | The working log — every version, every measurement, every retraction, the backlog |
| [`TEAM-DESIGN.md`](_AI-Study/TEAM-DESIGN.md) | Team composition study + the generation spec |

**The games themselves are not in this repo** — only the study is. Everything the study
wrote *is* here, including the game-side runner, so pointing a fresh clone at a Reborn
Yang install is one command:

```bash
cd _AI-Study && python3 tools/install_reborn.py
```

It builds the AI, installs it and the batch runner into the game, and makes the two small
host edits they need. Idempotent, reversible, and inert until you create the marker file
that switches it on.

Findings are from reading shipped builds and running the AI, not from playtesting.
Everything measured here is reproducible from the artifacts committed under
`_AI-Study/generated/`.
