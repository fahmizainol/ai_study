# Gym 1 (Abi, Bug) replacement team — TEAM-DESIGN.md §6, Intense curve, gym-1 row.
# Drop-in for the createPokemon/createTrainer block in Map078 (Gimnasio de Ciudad
# Cornalina). Replaces: DEWPIDER:14 / ANORITH:14 / VESPIQUEN:14 (bare, no items).
# Full 6-mon team, following Reborn's rule: every boss fields 6.
# All symbols verified against Realidea V4.1 PBS (pokemon.txt / tm.txt / items.txt).
# EV/IV order is v16: [HP, Atk, Def, Spd, SpA, SpD].
# WIN CONDITION: Sleep Powder + paralysis/speed control strip the player's tempo,
# Heracross closes.

# ROLE: lead/disruptor — near-perfect Sleep Powder (Compound Eyes), Light Screen
# support, Stun Spore catches the switch-in. Legal full evo at 14 (evolves at 12).
p0 = createPokemon("VIVILLON", 13, [:SLEEPPOWDER, :STRUGGLEBUG, :STUNSPORE, :LIGHTSCREEN])
p0.iv = [31,31,31,31,31,31]
p0.ev = [4,0,0,252,252,0]
p0.item = PBItems::ORANBERRY          # sustain; berries only at gym 1
p0.setAbility(1)                      # COMPOUNDEYES (slot 1)
p0.setNature(:TIMID)                  # setNature calls calcStats — keep it last

# ROLE: speed control / anti-Flying — Thunder Wave + Electroweb cripple the fast
# Flying counters for everyone behind it; Screech opens walls for the physical core.
# Electroweb is learnset lv15 (+1 leader privilege, same pool).
p1 = createPokemon("JOLTIK", 14, [:ELECTROWEB, :THUNDERWAVE, :FURYCUTTER, :SCREECH])
p1.iv = [31,31,31,31,31,31]
p1.ev = [4,0,0,252,252,0]
p1.item = PBItems::ORANBERRY
p1.setAbility(0)                      # COMPOUNDEYES (slot 0)
p1.setNature(:TIMID)

# ROLE: anti-counter — Water Bubble halves Fire damage and doubles Water STAB, so
# the "obvious" Fire answer loses; Spider Web traps it, Bug Bite eats its berry.
# Bubble Beam is learnset lv16 (+2 leader privilege, same pool).
p2 = createPokemon("DEWPIDER", 14, [:BUBBLEBEAM, :INFESTATION, :SPIDERWEB, :BUGBITE])
p2.iv = [31,31,31,31,31,31]
p2.ev = [252,0,0,0,252,4]
p2.item = PBItems::SITRUSBERRY
p2.setAbility(0)                      # WATERBUBBLE (only slot)
p2.setNature(:MODEST)

# ROLE: Sturdy anchor — guaranteed to move at least twice (Sturdy + Oran), spams
# multi-hit Rock and stacks Rock Tomb slows; second anti-Flying wall-breaker.
p3 = createPokemon("DWEBBLE", 14, [:ROCKBLAST, :ROCKTOMB, :FEINTATTACK, :WITHDRAW])
p3.iv = [31,31,31,31,31,31]
p3.ev = [252,252,4,0,0,0]
p3.item = PBItems::ORANBERRY
p3.setAbility(0)                      # STURDY (slot 0)
p3.setNature(:ADAMANT)

# ROLE: glue/bruiser — Brick Break breaks the player's own screens and hits the
# Rock/Steel that walls Bug; Battle Armor + bulk investment makes it sticky.
# ROCKTOMB / BRICKBREAK via TM (verified in tm.txt).
p4 = createPokemon("ANORITH", 14, [:ROCKTOMB, :BRICKBREAK, :WATERGUN, :HARDEN])
p4.iv = [31,31,31,31,31,31]
p4.ev = [252,252,4,0,0,0]
p4.item = PBItems::ORANBERRY
p4.setAbility(0)                      # BATTLEARMOR (only slot)
p4.setNature(:ADAMANT)

# ROLE: ace/closer — real STAB (Brick Break TM), Night Slash is level-1 learnset,
# Aerial Ace mirrors bug-vs-bug, Rock Tomb punishes Flying. Jolly + 252 Spe
# outspeeds everything unslowed at this stage; cleans after the team's chip.
p5 = createPokemon("HERACROSS", 15, [:BRICKBREAK, :NIGHTSLASH, :AERIALACE, :ROCKTOMB])
p5.iv = [31,31,31,31,31,31]
p5.ev = [4,252,0,252,0,0]
p5.item = PBItems::SITRUSBERRY
p5.setAbility(1)                      # GUTS (slot 1) — burn/para backfires
p5.setNature(:JOLLY)

party = [p0, p1, p2, p3, p4, p5]
trainer = createTrainer(33, "Abi", party, [PBItems::POTION, PBItems::POTION])
result = customTrainerBattle(trainer, "...")   # keep the original end-speech line
pbSet(1, result == BR_WIN ? 0 : 1)             # keep whatever the original event set

# SELF-CHECK (spec §6.2/§6.3):
# [x] 6 mons — Reborn rule: every boss fields 6
# [x] species in dex: VIVILLON/JOLTIK/DEWPIDER/DWEBBLE/ANORITH/HERACROSS
# [x] evolution-legal levels (Vivillon evolves @12; others unevolved/basic)
#     — fixes the original lv-14 Vespiquen (evolves @21)
# [x] moves: level-up ≤ level except BUBBLEBEAM (lv16, +2) and ELECTROWEB
#     (lv15, +1), both flagged; ROCKTOMB/BRICKBREAK TM-legal per tm.txt
# [x] items exist in items.txt; berries only + trainer Potions (gym-1 row)
# [x] EVs ≤ 510 total, ≤ 252/stat (508 each); IV 31 — Intense curve, no cheat
#     tier at gym 1
# [x] ability slots checked against Abilities= lines (indices in comments)
# [x] rubric: win condition (Heracross), lead job (sleep/screen), coverage
#     (Fighting/Rock/Dark/Flying/Water/Electric/Bug ≥ neutral on everything
#     relevant this early), anti-counter (Dewpider vs Fire, Joltik + double
#     Rock Tomb vs Flying), glue (Anorith/Dwebble), item logic (sustain
#     berries; no itemless mons)
# [ ] AI-DEP: none — all sets are greedy-good; sleep/para/Rock Tomb/Spider Web
#     work under stock v16 AI and get better with the upgrade
