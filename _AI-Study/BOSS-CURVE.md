# The Boss Power Curve — Reborn Yang Intense, measured

Companion to `TEAM-DESIGN.md` §3–§4. That section established *what* Reborn's bosses
carry (items, custom moves, IVs, EV totals). This one asks how the power actually
**progresses**, in a currency the player can be compared against, and answers a
question the EV column alone cannot: where does Reborn stop making its teams better
and start making them illegal?

All numbers regenerate with `python3 tools/boss_curve.py` (`--json` for the raw rows).
Sources: `extracted/reborn-trainers-full.json` (Intense = `pid 100`), Reborn's own
`PBS/PBS/pokemon.txt` + `gen8pokemon.txt`, and `Scripts/MultipleForms.rb` for the forms
that override base stats.

## 1. Effective BST — the one metric that makes bosses comparable to a player

A boss with 1,400 EVs and a player with 510 cannot be compared on BST, because most of
the boss's stats aren't in its BST. Both terms enter the stat formula through the same
bracket:

```
stat = floor( (floor((2*Base + IV + floor(EV/4)) * L/100) + 5) * nature )
```

`+1 base` adds 2 to that bracket; `+8 EV` also adds 2. So **1 BST point = 8 EVs**, and
because base and EV pass through the same `* L/100`, the exchange rate is *level
independent* — it does not change with the level cap. Define

```
eBST = BST + max(0, EV_total - 510) / 8
```

which reads as: *the BST a legal, 510-EV Pokémon would need to have the boss's real
stats.* Since every Intense mon already runs 31 IVs and the player can too, IVs need no
adjustment and eBST is a fair like-for-like.

(Worth stating because it is easy to over-estimate: a 500-BST mon with 1,000 EVs is a
**561**, not a 600. 490 excess EV buys 61 base points.)

## 2. The ladder

`cap` is `LEVELCAPS[badge-1]` — the cap actually in force for that fight.
`gap` is `cap − boss ace`. `>510` counts party members over the legal EV cap.

| # | boss | lv | cap | gap | BST | min | max | spread | NFE | EV | >510 | **eBST** | Δ |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Julia | 17–19 | 20 | +1 | 397 | 300 | 490 | 190 | 3 | 504 | 0 | **397** | — |
| 2 | Florinia | 23–25 | 25 | +0 | 450 | 305 | 495 | 190 | 1 | 353 | 0 | **450** | — |
| 3 | Corey | 28–30 | 30 | +0 | 460 | 305 | 535 | 230 | 2 | 471 | 0 | **460** | — |
| 4 | Shelly | 34–37 | 35 | −2 | 487 | 454 | 515 | 61 | 0 | 491 | 0 | **487** | — |
| 5 | Shade | 39–42 | 40 | −2 | 472 | 410 | 520 | 110 | 1 | 468 | 0 | **472** | — |
| 6 | Kiki | 44–47 | 45 | −2 | 501 | 410 | 550 | 140 | 0 | 546 | 1 | **506** | +5 |
| 7 | Aya | 45–47 | 50 | +3 | 508 | 480 | 525 | 45 | 0 | 537 | 1 | **512** | +4 |
| 8 | Serra | 49–53 | 55 | +2 | 494 | 450 | 535 | 85 | 0 | 669 | 6 | **514** | +20 |
| 9 | Noel | 55–57 | 60 | +3 | 507 | 470 | 570 | 100 | 1 | 582 | 6 | **516** | +9 |
| 10 | Radomus | 60–63 | 65 | +2 | 518 | 480 | 600 | 120 | 0 | 531 | 5 | **521** | +3 |
| 11 | Luna | 65–69 | 70 | +1 | 532 | 500 | 600 | 100 | 0 | 736 | 6 | **561** | +28 |
| 12 | Samson | 69–72 | 70 | −2 | 548 | 480 | 770 | 290 | 0 | 681 | 6 | **570** | +21 |
| 13 | Charlotte | 70–74 | 75 | +1 | 524 | 505 | 534 | 29 | 0 | 762 | 6 | **555** | +31 |
| 14 | Terra | 75–78 | 75 | −3 | 532 | 430 | 600 | 170 | 0 | 825 | 6 | **572** | +39 |
| 15 | Ciel | 75–77 | 80 | +3 | 491 | 455 | 510 | 55 | 0 | 801 | 6 | **527** | +36 |
| 16 | Adrienn | 81–85 | 85 | +0 | 504 | 380 | 580 | 200 | 0 | 1010 | 6 | **566** | +62 |
| 17 | Titania | 85–90 | 90 | +0 | 530 | 495 | 600 | 105 | 0 | 1239 | 6 | **621** | +91 |
| 18 | Amaria | 90–92 | 90 | −2 | 508 | 457 | 535 | 78 | 0 | 1184 | 6 | **592** | +84 |
| 19 | Hardy | 90–94 | 95 | +1 | 508 | 470 | 567 | 97 | 0 | 512 | 6 | **508** | +0 |
| 20 | Saphira | 95–100 | open | — | 586 | 501 | 708 | 207 | 0 | 1406 | 6 | **697** | +112 |
| 21 | Heather (E4) | 101–105 | open | — | 543 | 499 | 600 | 101 | 0 | 1295 | 6 | **641** | +98 |
| 22 | Elias (E4) | 103–105 | open | — | 550 | 288 | 720 | 432 | 0 | 1194 | 6 | **635** | +85 |
| 23 | Anna (E4) | 104–105 | open | — | 558 | 490 | 600 | 110 | 0 | 1376 | 6 | **666** | +108 |
| 24 | Lin (final) | 105 | open | — | 552 | 505 | 650 | 145 | 1 | 1457 | 6 | **670** | +118 |

## 3. Three findings

### 3.1 The BST "plateau" is an artifact of measuring the wrong currency

In nominal BST the curve flatlines: 508 at badge 7, 508 at badge 19, twelve badges of
nothing. Amaria (badge 18, 508) is statistically indistinguishable from Aya (badge 7,
508). In **eBST** it never stops climbing — 397 → 512 → 621 → 697.

And the two halves of the game contribute almost exactly the same amount of power:

| segment | Δ eBST | from species | from EV cheat |
|---|---|---|---|
| badges 1 → 7 | **+115** | +111 | +4 |
| badges 7 → final | **+158** | +44 | **+114** |

Reborn buys its first third of difficulty with Pokémon and its last two thirds with
EVs, at roughly equal rates. This is the quantitative form of the "fair layer / unfair
layer" split described in `TEAM-DESIGN.md` §3.

### 3.2 The switchover is badge 8 (Serra), and it is exact

Serra's Intense roster is **species-identical to her Normal roster** — the only leader
in the first eight for which that is true. The entire Intense delta is EVs: all six of
her mons break the 510 cap (669 mean), worth +20 eBST. Before her, no boss has more
than one over-cap member; from her on, every boss has six. After that the EV totals
climb 582 → 736 → 762 → 825 → 1010 → 1239 → 1457 while nominal BST does nothing.

Two structural notes on the first half, which is where a *fair* difficulty curve lives:

- **The floor is the knob, not the ceiling.** Max BST moves 490 → 535 across badges
  1–8 (+9%); min BST moves 300 → 450 (+50%). Badges 1–3 each ship one free kill
  (Alolan Geodude 300, Ferroseed 305, Mareanie 305). Shelly at badge 4 ends that
  permanently — her spread is 61, Aya's is 45.
- **Every low floor after badge 4 is an ability pick, not filler**: Adrienn's Mawile
  380 (Huge Power), Terra's Clodsire 430 (Unaware), Elias's Ditto 288 (Imposter,
  which is why his 432 spread is a meaningless number), and Lin's "Abra" — actually
  **PULSE Abra at 650 BST**, not a 310 Abra.

### 3.3 What the cheated EVs buy is breadth, not spikes

96.5% of Intense mons respect the 252-per-stat cap (117 of 3,331 break it — Titania's
Kingambit at 404 Atk, Anna's Altaria at 535 HP). The cheat is almost never a superhuman
single stat. It is **the absence of dump stats**:

```
legal player mon     252 / 252 /   4 /   0 /   0 /   0    (510)
Titania Duraludon    252 /   0 / 252 / 252 / 252 / 252   (1260)
```

So a 743-eBST Garchomp is not a scaled-up Garchomp — it is Garchomp's own spread with
~63 stat points bolted onto four slots that would normally sit empty. Same total power,
different shape, and it matters tactically: there is no stat it failed to invest in.

Largest single-Pokémon conversions:

| boss | Pokémon | EV | BST → eBST |
|---|---|---|---|
| Anna (E4) | Altaria | 1795 | 490 → **651** (+161) |
| Lin (final) | Garchomp | 1655 | 600 → **743** (+143) |
| Lin (final) | PULSE Abra | 1615 | 650 → **788** (+138) |
| Terra | Garchomp | 1512 | 600 → **725** (+125) |
| Saphira | Walking Wake | 1512 | 590 → **715** (+125) |
| Elias (E4) | Arceus | 1512 | 720 → **845** (+125) |

Three teams also carry a genuine species outlier: Samson swaps Normal's Lucario (525)
for a **Breloom-Bot — 770 BST, Steel-type** (the single largest Intense-only species
edit in the game; it alone moves his mean 508 → 548), Saphira runs Zygarde-Complete
(708), Elias runs Arceus (720).

**Hardy is the standing anomaly.** Badge 19, eBST **508**, sitting between Titania's
621 and Saphira's 697, with legal EVs (512) in the middle of a stretch where everyone
else runs 800–1400. Either an oversight or a deliberate breather; recorded here so a
future pass doesn't read it as a measurement error.

## 4. Where the level cap sits

`LEVELCAPS` (`Scripts/Reborn/SystemConstants.rb:7`) is one table for all difficulties —
Intense does not touch it. The `gap` column above, badges 1→19:

```
+1, 0, 0, −2, −2, −2, +3, +2, +3, +2, +1, −2, +1, −3, +3, 0, 0, −2, +1
```

Range −3..+3, mean +0.2. **Reborn's cap sits on the boss's ace all game and never
drifts more than three levels either way.** It is level *parity*, not a handicap — you
are never asked to fight meaningfully underlevelled, and you can never out-grind the
ladder either. The difficulty is entirely in the team, which is the point of §3.1.

Reborn enforces this in four places off the one table: `pokemon.obedient` set at battle
start (`PokeBattle_Battle.rb:525`), the obedience roll (`PokeBattle_Battler.rb:4390`),
EXP clamping to exactly the amount needed to reach the cap (`PokeBattle_Battle.rb:2745`,
gated on the `Hard_Level_Cap` switch), and EXP items (`PokemonUtilities.rb:1728`).

Realidea's own cap ladder (`084_PokeBattle_Battle.rb:2310`, commented `#capadorniveles`,
keyed to switches 4–11 = the stock `Defeated Gym N` switches) is `20/25/30/35/40/45/
50/55/100` — Reborn's `LEVELCAPS[0..7]` copied verbatim. But Realidea's aces are
14/20/26/33/38/40/45/48, so the same numbers land **2–7 levels above every boss**
instead of on them, and the cap never binds. Realidea's version also gates on
`level > cap` rather than clamping EXP to the cap, so a mon one level under can eat a
full battle's EXP and overshoot by several levels.

> The shipped adapter (`adapters/realidea/Level_Cap.rb`, commit `c23d8bd`) now uses an
> **Unbound-derived** curve with `vanilla`/`expert` modes, not a Reborn-derived one.
> The measurement above is recorded as a finding about Reborn, not as a proposal
> against that adapter. Had the goal been to match Reborn, parity with Realidea's own
> aces — `[15, 20, 26, 31, 36, 40, 45, 48, 51, 100]` — is what the data supports.

## 5. Correction to `TEAM-DESIGN.md` §3

The badge numbering in the §3 tables is wrong from badge 13 on: it lists Ciel at 14 and
Adrienn at 15, then jumps to Hardy 17 / Saphira 18. Terra's fight is keyed under the
name **`T3RR4`** and was missed, which dropped a slot; Titania was also skipped. The
data supports, monotone in Normal-mode ace level with no gaps:

**13 Charlotte (72) → 14 Terra (75) → 15 Ciel (78) → 16 Adrienn (81) → 17 Titania (90)
→ 18 Amaria (92) → 19 Hardy (95) → Saphira (100).**

Kiki (`class Sensei`, badge 6) is also absent from the §3 Intense table.

## 6. Bearing on the Realidea regeneration spec

`TEAM-DESIGN.md` §6.2's cheat-tier bands convert to:

| band | EV total | Δ eBST |
|---|---|---|
| gym 6 | ~550–650 | +5 … +18 |
| gym 7 | ~650–750 | +18 … +30 |
| gym 8 | ~700–800 | +24 … +36 |

That is roughly Reborn's **Kiki/Aya** tier (+4 … +5) to **Charlotte** tier (+31), not
its Adrienn/Titania tier (+62 … +91). Defensible — Realidea's aces top out at 48 and
its rosters already carry *higher* nominal BST than Reborn's (gym 8 Bay 545 vs Serra
494) — but it is a choice, and it should be a recorded one rather than an accident.

The transferable design rule from §3.2, which Realidea's current rosters violate: raise
the floor before the ceiling. Realidea keeps a Wobbuffet (405) in gym 7; Reborn has no
free kill after gym 3.

## 7. Caveats

- eBST is a **total-power** equivalence. It says nothing about items, natures or
  abilities, which are a real part of the gap, and it flattens distribution (see §3.3).
- Form base stats come from `MultipleForms.rb` via a brace-matched parser. This matters:
  a naive regex reads past a form declaring no `:BaseStats` and picks up the next
  form's — scoring Urshifu-**Rapid** (no override, 550) as Urshifu-**Dyna X** (650).
  Only three forms in these 24 teams override stats: Zygarde-Complete 708,
  Breloom-Bot 770, PULSE Abra 650. Every regional variant present shares its base BST.
- Fights are matched on `(name, class, pid=100)` with a 6-mon party. Bosses with
  multiple story variants (Titania, Amaria) resolve to the numbered class carrying a
  `pid 100`; `boss_curve.py` warns on stderr if a variant goes missing after a data
  refresh.
