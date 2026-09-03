# Pokémon Fangame Battle AI — Study Folder

Self-contained workspace for comparing battle AI across the games in `../`.
Started 2026-09-03. Covers **two engines**: Essentials (Ruby) and CFRU (C, GBA).

```
_AI-Study/
├── README.md                      you are here
├── ANALYSIS.md                    the write-up — tables, per-game detail, file:line citations
├── TEAM-DESIGN.md                 trainer team composition: Reborn (Normal+Intense) vs Realidea,
│                                  plus the LLM generation spec for replacement teams
├── tools/
│   ├── marshal_rb.py              Ruby Marshal 4.8 reader for .rxdata
│   └── extract_rxdata.py          CLI: dump Ruby source from Scripts/PluginScripts bundles
└── extracted/
    ├── ashen-frost-MANIFEST.txt   what is ACTUALLY compiled into Ashen Frost's build
    ├── hegemony-MANIFEST.txt      same for Hegemony
    ├── unbound-MANIFEST.txt       GBA/CFRU — ROM hash, pinned commit, private-surface list
    ├── hegemony-PluginScripts.rxdata   raw bundle pulled from GitHub (source not in repo)
    ├── ashen-frost/               Consistent AI (live) + Difficulty Modes
    └── hegemony/                  Phantombass AI 1.0.0
```

The tools here are Essentials-only. **GBA hacks need a completely different route** —
see `unbound-MANIFEST.txt` and the GBA section at the end of `ANALYSIS.md`. Short
version: don't decompile the ROM, clone the engine (CFRU) and find the undefined
`extern`s, which are the only parts the hack keeps private.

## Start here

Read `ANALYSIS.md`. It has the two comparison tables and the per-game breakdowns.

`SIM-SPEC.md` is the forward-looking piece: a spec for probing each AI's decisions over a
shared scenario corpus, so an AI port can be measured instead of eyeballed. Note that
Reborn Yang already ships a headless battle harness (`PokeBattle_TestEnvironment.rb`) and a
structured decision record (`PokeBattle_AI_Info`) — start there, don't build from zero.

## Quick recipes

```bash
cd tools

# What is really compiled into a shipped build? (the folder can lie — see below)
python3 extract_rxdata.py "../../Ashen Frost - Windows/Data/PluginScripts.rxdata" /tmp/x --list

# Dump every plugin's Ruby source
python3 extract_rxdata.py "../../Ashen Frost - Windows/Data/PluginScripts.rxdata" ./out

# v16-era games keep everything in one bundle, no Plugins folder exists
python3 extract_rxdata.py "../../Realidea V4.1/Data/Scripts.rxdata" ./out

# Reborn-family: plaintext Scripts/ + a tiny Scripts.rxdata. Extract the stub anyway —
# it proves whether the folder is live. 4 KB here = a loader, so the folder IS the game.
python3 extract_rxdata.py "../../Reborn Yang/Reborn Yang/Data/Scripts.rxdata" /tmp/x --list
```

Grep vocabulary that pays off:

| Pattern | Tells you |
|---|---|
| `OMNISCIENT_AI` | Phantombass-family knowledge switch |
| `PBTrainerAI\.` / `has_skill_flag?` | skill gating (v16-v20 / v21 style) |
| `pbAIRandom` | is move choice deterministic or a roulette |
| `@battle.choices[` | possible turn-prediction cheat — **verify, see caveat** |
| `!pbOwnedByPlayer` | asymmetric enemy-favouring mechanics |
| `revealedMoves` | whether a knowledge model exists and who it serves |

## Two traps that produce confidently wrong answers

**1. The plugin folder is not what runs.** `meta.txt` = enabled, `meta.txts` = disabled —
but that only matters if the game recompiles. `PluginManager.needCompiling?` opens with
`return false if !$DEBUG`, and `runPlugins` then evals *every* entry in
`Data/PluginScripts.rxdata` unconditionally. In a release build the compiled bundle is
authoritative and the folder state is cosmetic.

This is not hypothetical: Ashen Frost's folder advertises Phantombass AI as enabled, but
the shipped bundle contains **Consistent AI** and no Phantombass code at all.
Always check the manifest.

**2. Do not scan for zlib headers.** `.rxdata` is Ruby Marshal 4.8. A header scan looks
like it works and silently drops sections — it missed an entire 15,000-line plugin on the
first pass here. Use `tools/marshal_rb.py`.

## Caveat when calling something a cheat

An AI reading `battle.choices` may simply be emulating a mechanic that legitimately
depends on turn order — Stakeout doubles damage against a switching target, Zoom Lens
keys off moving second. Phantombass's reads are all of this kind. Consistent AI's are
not: it checks whether you picked Wide Guard, and whether Sucker Punch will fail, at
30/50/70% by difficulty. Read the enclosing handler before judging.

## Open threads

- **Unconfirmed:** "Ashen Frost runs Consistent AI" is inferred from the bundle plus the
  `$DEBUG` check, not observed. Booting the game and reading the
  `Loaded plugin: ==<name>==` console lines would settle it in one line.
- **Unconfirmed:** the Unbound write-up is read from public CFRU @ `b637a27` (Jan 2025),
  but the ROM is from Mar 2023 and was built against a private pinned snapshot. Ghidra +
  GhidraGBA on the ROM would close it. Also unresolved: how Unbound's four UI difficulties
  (Vanilla/Difficult/Expert/Insane) map onto CFRU's `OPTIONS_*_DIFFICULTY` values — that
  mapping is ROM data, and several cheats key off `>= OPTIONS_EXPERT_DIFFICULTY`.
- Everything here is static analysis. No playtesting; team composition and level curves
  are largely out of scope.
- Not yet examined: Bloodborne, Pokemon Empire (+ Expanded), Slipstream RL,
  Grueling Gold 4.0 / v20.1 — all present in `../`.
