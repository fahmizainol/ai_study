# Player Curve — fitting Run & Bun's power curve to Realidea

Status: **adapters installed and tested in-engine (2026-09-28); the generator moves to the
rnb curve in the boss-generator session (section 4). Its gates stay as installed.** Companion to [LEVEL-SCALING.md](LEVEL-SCALING.md).

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

**Agreed (in progress in that session, not installed):**
1. `realidea_level_curve.json` has an `rnb` column; set `active_mode` to `rnb` and
   regenerate the gyms and trainers on it.
2. Emit `TEAM_OVERRIDES_CURVE = "<active_mode>"` from `emit_registry.py` in the same
   change. Until then Level_Scaling assumes `"expert"` for generated overrides, which is
   correct for the current install and wrong the moment they are generated on `rnb`:
   they would be raised twice.
3. Measure at 50 ms on fix2's draws against the current install; install only on the
   user's word.

**Not agreed -- the installed generator choices stay:** Ubers from gym 4, the ace rule with
box legendaries from gym 6, `LEGEND_MAX` 6. The Run & Bun fit in section 1 suggested
pseudos off the 580-BST gate, minor legendaries from gym 2, `LEGEND_MAX` 1, box legendaries
for the Champion only, and Ultra Beasts and Ubers from gym 7. The user declined those
(2026-09-28): only the level change was meant. They are recorded here as the measured
alternative, not as pending work.

## 5. Moves and held items: open, not rationed (built 2026-09-28)

Run & Bun's TM / tutor / held-item tabs were placed by badge first (the drip-fed draft in
git history, 2026-09-28). The user declined that shape: Run & Bun rations the player to
prop up a weak AI, and Realidea's bosses run a search AI with these moves and items from
gym 1. What shipped (`Player_Services`, switch `Data/player_services.txt`):

**Realidea before:** no move tutor anywhere; 51 of 103 TMs/HMs with no source and 92
`tm.txt` moves with no TM, so 142 of 194 TM/tutor moves unlearnable; no source for Choice
items, Assault Vest, Focus Sash, Rocky Helmet, Muscle Band, Wise Glasses, the herbs, Eject
Button, Red Card or any Gem. (Counts after the `extract_item_sources.py` fix, which now
reads `if`-branch gifts and Bea's shard list: 304 -> 353 obtainable items.)

**The code NPC's menu:**

| entry | what it does |
|---|---|
| Badge rewards (N waiting) | shown only while something waits; section 2's table |
| Teach a move | free; Pokémon -> type -> move ("Ice Beam · ICE · 90"): any `tm.dat` move it can learn (form-aware) and does not know |
| Remember moves | the game's Move Reminder, which now also lists the line's egg moves |
| Buy held items | three shops at own prices (PBS prices are placeholders) |
| Enter a code | the NPC's original prompt |

**Shop:** battle items (premium 8,000: Choice Band / Scarf / Specs, Life Orb, Assault
Vest, Leftovers, Focus Sash, Weakness Policy, Expert Belt, **from 2 badges**; utility
3,000: Rocky Helmet, Air Balloon, Eviolite, Light Clay, herbs, Eject Button, Red Card,
lenses, weather rocks, terrain seeds, orbs...), type boosters / plates / Gems 1,000,
berries 500 (Lum, Sitrus, pinch and resist berries). 121 items. A Rare Candy is 4,800.

**Egg moves:** every stage of the line's `eggEmerald.dat` list (an incense baby and the
stage that hatches without it both count); the Alolan Vulpix line (form 1) uses
Showdown's gen 7 list instead of fire Vulpix's.

Verified in-engine (23/23 with the rest of this doc): Weavile can be taught 59 moves
including Knock Off; Alolan Ninetales gets Aurora Veil, fire Ninetales does not; Weavile's
Move Reminder has Icicle Crash; the Alolan line gets Freeze-Dry and not Flare Blitz; all
121 shop items resolve. Not verified: the menus driven by hand.

Not coverable without a PBS recompile: 27 Run & Bun moves Realidea has no learner list for
(Play Rough, Hurricane, Aura Sphere, Hydro Pump...); Heavy-Duty Boots, Room Service and
Eject Pack are not in Realidea's item data. Realidea's Knock Off is 20 power (its move data).
