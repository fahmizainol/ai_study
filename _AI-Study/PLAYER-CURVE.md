# Player Curve — fitting Run & Bun's power curve to Realidea

Status: **adapters written and tested in-engine (2026-09-28); generator half handed to
the boss-generator session.** Companion to [LEVEL-SCALING.md](LEVEL-SCALING.md).

## 1. What Run & Bun does, measured

From its Pokémon Locations sheet (5 tabs), its Item Locations sheet (Mega Stones tab), its
evolution file and its 23 bosses (`generated/rnb/trainers.json`):

| | bosses | player |
|---|---|---|
| legendaries | 1 per team from gym 1 (Kubfu, Zygarde-10%, Zeraora, Meloetta...); box legendaries only at the story climax and the E4 | roamers just before gym 8, one mythical for badge 8; box legendaries never |
| megas | exactly 1 per boss from gym 3 | first stone before gym 4, 9 by gym 5 |
| 600-BST pseudos, fully evolved | from Maxie at Chimney | Metagross, Kommo-o before Maxie at Chimney (cap 54); Tyranitar, Garchomp, Dragonite by Flannery (57) |
| Ultra Beasts | 1 per team after gym 5 | never |

Realidea before this change: first evolved pseudo at gym 7 (evolution levels 45–64 against
gym caps ending at 61), stones buyable at gym 7, megas locked to Simon's Ruta 13 event
(switch 512) for everyone, legendaries only after the Champion.

Both games have **8 badges, a last boss before the league, then the Champion**, so the fit
is one-to-one by badge.

## 2. What ships (no map, event or PBS edit)

| piece | section | switch | what it does |
|---|---|---|---|
| rnb cap curve | `Level_Cap` | `Data/level_cap_mode.txt` = `rnb` | caps 21 25 35 42 57 69 85 91 95, Champion 99 |
| catch-up EXP | `Level_Cap` | on; `Data/exp_multiplier.txt` = `off` or a flat number | ×(1 + 0.25·(gap−1)), max ×4, stops at the cap, never below the plain award |
| trainer remap | `Level_Scaling` | `Data/level_scaling.txt` (already on) | every fight moved to the active curve before the anchor/leash |
| wild remap | `Level_Scaling` | `Data/wild_scaling.txt` | random encounters moved from the original ladder |
| badge rewards | `Badge_Rewards` | `Data/badge_rewards.txt` | the code NPC (common event 79 → `pbCodeMysteryGift`) offers each badge's reward |
| early megas | `Badge_Rewards` | same file | `pbCanMegaEvolve?` reads switch 512 as on from 3 badges, restored after the check |

**Trainer remap source ladder** (`RealideaLevelScaling.inline_source`):
- event party, or a filler override that keeps its levels → `"original"` (the nine leader
  aces 14…51 and the Champion's 66, the x-axis of `generate_bosses.remap()`);
- a generated override (its ace differs from the event's) → `TEAM_OVERRIDES_CURVE`,
  `"expert"` when the registry does not declare one;
- a `balanceo` fight → not remapped. The mark is used up by the next trainer, and cleared
  after wild battles, gifts and each map-scene update. `Graphics.frame_count` was tried
  and rejected: measured in-engine, it does not advance under a frozen screen.

**Rewards** (pick one; gifts at cap − 3, evolved as far as that level allows):

| badge | Pokémon | stones |
|---|---|---|
| 1 | Elekid / Magby / Smoochum | — |
| 2 | Heracross / Pinsir | — |
| 3 | Axew / Gible | 1 of Ampharosite, Aggronite, Pidgeotite |
| 4 | Larvitar / Beldum | 1 of Lopunnite, Altarianite, Absolite |
| 5 | Dratini / Bagon / Deino | 1 of Garchompite, Scizorite, Gyaradosite |
| 6 | Goomy / Jangmo-o | 2 of the rest |
| 7 | Latias / Latios / Raikou / Entei / Suicune / Heatran | 2 of the rest |
| 8 | Mew / Jirachi / Celebi / Victini | — |

Tyranitarite, Metagrossite and Salamencite are withheld, as in Run & Bun. Box legendaries
stay behind switch 536 (set after the Champion). Claims live in `$Trainer.regalosmis`.

## 3. Verified

- Ruby unit tests: `tests/test_realidea_level_cap.rb` (17), `test_realidea_level_scaling.rb`
  (17), `test_realidea_badge_rewards.rb` (10); all other Realidea suites still pass.
- In-engine (`tests/ingame_curve_selftest.rb`, a test-only section run in a scratch game
  copy under Proton): 15/15. Real `createTrainer` filler 40/38 → 69/57; the installed Abi
  override moved expert → rnb (ace 21); `balanceo` fight unchanged; Ruta 1 wild 3–4 → 5–6;
  ×3.75 EXP at 12 below the cap; Gible@39 → Gabite, Beldum@54 → Metagross, Goomy@60 → Goodra
  through the game's own `pbCheckEvolution`; all 11 hooks wired.
- **Not verified:** the NPC dialogue driven by hand, and the stock RGSS1 player
  (`Game (old).exe`). The sections avoid post-1.8 syntax.

## 4. Generator half (boss-generator session)

1. `realidea_level_curve.json` has an `rnb` column; set `active_mode` to `rnb` and
   regenerate the gyms and trainers.
2. Emit `TEAM_OVERRIDES_CURVE = "<active_mode>"` from `emit_registry.py`. Until then
   Level_Scaling assumes `"expert"` for generated overrides, which is correct for the
   current install and wrong the moment they are generated on `rnb`: they would be
   raised twice.
3. Gates, per the Run & Bun fit: pseudos gated by evolution level only (drop them from
   the 580-BST gate); minor legendaries (≤ 600, not box) from gym 2 inside the power band;
   `LEGEND_MAX = 1` (Champion 2); box legendaries Champion only; Ultra Beasts from gym 7, max
   1; the Uber band from gym 7; megas unchanged (1 per team from gym 4, now able to fire).
