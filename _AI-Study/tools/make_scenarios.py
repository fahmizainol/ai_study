#!/usr/bin/env python3
"""Generate the Tier-1 scenario corpus (SIM-SPEC.md §3, §5).

Scenarios are written here with readable internal names; this resolves them to numeric
IDs against the game's plaintext PBS and emits two artifacts:

  <game>/Data/ai_scenarios.txt   engine-readable, IDs only, no assertions
  scenarios.json                 the same corpus WITH assertions, for check_scenarios.py

Splitting them this way keeps the engine side dependency-free (no JSON in RGSS) and keeps
the judgement in Python, where iterating does not cost a game launch.

Usage:
    python3 make_scenarios.py --pbs "<game>/PBS/PBS" \
        --out-engine "<game>/Data/ai_scenarios.txt" --out-json scenarios.json
"""
import argparse
import json
import os
import re


def load_pbs(pbs):
    mv, sp, it, ab = {}, {}, {}, {}
    with open(os.path.join(pbs, 'moves.txt'), encoding='utf-8', errors='replace') as f:
        for line in f:
            p = line.split(',')
            if len(p) >= 2 and p[0].strip().isdigit():
                mv[p[1].strip()] = int(p[0])
    with open(os.path.join(pbs, 'items.txt'), encoding='utf-8', errors='replace') as f:
        for line in f:
            p = line.split(',')
            if len(p) >= 2 and p[0].strip().isdigit():
                it[p[1].strip()] = int(p[0])
    # ab[name] = [ability0, ability1, hidden] — the slot layout Reborn's
    # PokeBattle_Pokemon#ability indexes into ([ret1,ret2,h1][abilityIndex]), so a
    # scenario's ability NAME can be resolved to the slot index setAbility expects.
    cur_id, cur_name = None, None
    with open(os.path.join(pbs, 'pokemon.txt'), encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            m = re.match(r'^\[(\d+)\]$', line)
            if m:
                cur_id, cur_name = int(m.group(1)), None
            elif cur_id is not None and line.startswith('InternalName='):
                cur_name = line.split('=', 1)[1].strip()
                sp[cur_name] = cur_id
            elif cur_name and line.startswith('Abilities='):
                regs = [a.strip() for a in line.split('=', 1)[1].split(',') if a.strip()]
                ab.setdefault(cur_name, [None, None, None])
                for i in range(min(2, len(regs))):
                    ab[cur_name][i] = regs[i]
            elif cur_name and line.startswith('HiddenAbility'):
                hid = [a.strip() for a in line.split('=', 1)[1].split(',') if a.strip()]
                ab.setdefault(cur_name, [None, None, None])
                ab[cur_name][2] = hid[0] if hid else None
    return mv, sp, it, ab


# Standard Gen-3+ nature order; both engines use it (Reborn PBNatures, v19
# GameData::Nature). Reborn's scenario format is numeric, Hegemony's is the name.
NATURE_IDS = {n: i for i, n in enumerate([
    'HARDY', 'LONELY', 'BRAVE', 'ADAMANT', 'NAUGHTY', 'BOLD', 'DOCILE', 'RELAXED',
    'IMPISH', 'LAX', 'TIMID', 'HASTY', 'SERIOUS', 'JOLLY', 'NAIVE', 'MODEST',
    'MILD', 'QUIET', 'BASHFUL', 'RASH', 'CALM', 'GENTLE', 'SASSY', 'CAREFUL',
    'QUIRKY'])}


def mon(species, level=50, moves=(), item=None, hp_pct=None, status=None,
        stages=None, ability=None, nature=None, ev=None, effects=None,
        pp_all=None, last_move=None):
    """ability/nature are NAMES ('WATERABSORB', 'ADAMANT'); ev is {'atk': 252, ...}.
    Probes pin nature=HARDY and ability slot 0 when unspecified, so these are only
    needed when a scenario depends on a specific one (e.g. an absorb-ability target
    whose species has two possible abilities).

    effects is {name: value} of battler effects applied on-field — see
    EFFECT_NAMES. Values are ints (perish/toxic counters, sub HP, seeder index
    for leechseed where 0 = the player active, 1 = curse on) EXCEPT choiceband,
    whose value is the locked move's NAME (resolved per engine). pp_all sets
    every move's PP (0 = the +200 forced-out trigger).

    last_move is a move NAME and seeds the PORTABLE AI's own memory with "this is
    what I clicked last turn" (AI_Harness.rb seed_portable_memory). On its own it
    changes nothing; paired with effects={'tantrum': 1} it states the whole position
    the 0.6.2 move_memory rule reads -- the engine refused this exact move last
    turn."""
    return {'species': species, 'level': level, 'moves': list(moves), 'item': item,
            'hp_pct': hp_pct, 'status': status, 'stages': stages or {},
            'ability': ability, 'nature': nature, 'ev': ev or {},
            'effects': effects or {}, 'pp_all': pp_all, 'last_move': last_move}


# ---------------------------------------------------------------------------
# Move padding for AI-side Pokemon.
#
# WHY THIS EXISTS. PBAI classifies each Pokemon into a role at trainer-load time
# (Phantombass AI/03_AI_Roles.rb:435 assign_roles) and hard-gates two subsystems on the
# result: get_move_score:2184 zeroes EVERY status move when the role is :NONE, and
# get_switch_score:1769 refuses to evaluate switching at all. A sparse 1-2 move test
# Pokemon falls through every classifier branch, lands on :NONE, and the AI then looks
# like it "refuses to heal" and "never switches" — neither of which is true. That cost
# three false findings before it was caught (SIM-SPEC.md 9.4).
#
# WHY THESE MOVES. assign_roles awards :PHYSICALBREAKER for `physical_moves >= 2` and
# ignores type entirely, so two physical moves are sufficient to earn a role. The fillers
# are therefore all physical, all weak (30-40 BP), and deliberately NOT members of any
# role-trigger list — adding a setup move would suppress :TANK (see the `&&
# !roles.include?(:SETUPSWEEPER)` guard at :466), and Toxic/Taunt/Thunder Wave/Stealth
# Rock etc. each mint a role of their own and would change what is being measured.
#
# Three types are used rather than one so that a single immunity cannot zero the whole
# filler set — a target immune to all of a Pokemon's moves produces a flat score vector,
# which makes must_not_choose_move assertions pass by coin flip (see check_scenarios.py
# `degenerate`).
FILLER_MOVES = ['POUND', 'PECK', 'TACKLE', 'LICK']   # Normal / Flying / Normal / Ghost


def pad_to_four(m):
    """Return a copy of m padded to a 4-move set with weak physical fillers."""
    moves = list(m['moves'])
    for f in FILLER_MOVES:
        if len(moves) >= 4:
            break
        if f not in moves:
            moves.append(f)
    out = dict(m)
    out['moves'] = moves
    return out


# ---------------------------------------------------------------------------
# The corpus. Each assertion states a property any competent AI must satisfy —
# NOT what one particular AI happened to do. See SIM-SPEC.md §3 Tier 1.
# ---------------------------------------------------------------------------
CORPUS_V1 = [
    # --- kill recognition -------------------------------------------------
    # NAMING A SPECIFIC LETHAL MOVE IS NOT A PROPERTY OF GOOD PLAY. Against a target this
    # low, several moves kill — even a 40 BP filler — and Reborn scores every lethal move
    # identically (121) because it does not rank overkill. `must_choose_move_in` therefore
    # tests which of several equally-correct moves the roulette happened to land on. The
    # real property is "take a kill, don't set up", so assert that instead.
    ('lethal_ko_obvious', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'SWORDSDANCE']),
     mon('ALAKAZAM', 50, ['PSYCHIC'], hp_pct=6),
     [('must_not_choose_move', 'SWORDSDANCE'),
      ('score_gt', 'EARTHQUAKE', 'SWORDSDANCE')]),
    ('lethal_prefer_kill_over_setup', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'SWORDSDANCE', 'PROTECT']),
     mon('MAGNEZONE', 50, ['THUNDERBOLT'], hp_pct=8),
     # Same over-specification as lethal_ko_obvious, but it only showed up on Realidea:
     # there a 40 BP filler also kills at 8% HP, while on Reborn it fell just short. An
     # assertion that holds on one engine by a damage-roll margin is not a property.
     [('must_not_choose_move', 'SWORDSDANCE'),
      ('score_gt', 'EARTHQUAKE', 'SWORDSDANCE')]),
    ('lethal_vs_healthy_target_may_setup', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'SWORDSDANCE']),
     mon('ALAKAZAM', 50, ['PSYCHIC'], hp_pct=100),
     [('must_choose_any',)]),

    # --- type immunity ----------------------------------------------------
    ('immunity_ground_vs_flying', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'DRAGONCLAW']),
     mon('SKARMORY', 50, ['BRAVEBIRD']),
     [('must_not_choose_move', 'EARTHQUAKE'),
      ('score_gt', 'DRAGONCLAW', 'EARTHQUAKE')]),
    # The alternative move must be effective in EVERY generation the corpus runs on.
    # Earthquake was not: Gengar keeps Levitate in pre-Gen-7 data, so on Realidea both
    # Earthquake AND Body Slam score 0 and the comparison is between two immunities —
    # a portability defect in the scenario, not an AI failure. Shadow Ball hits Gengar
    # in every generation.
    ('immunity_normal_vs_ghost', 0,
     mon('SNORLAX', 50, ['BODYSLAM', 'SHADOWBALL']),
     mon('GENGAR', 50, ['SHADOWBALL']),
     [('must_not_choose_move', 'BODYSLAM'),
      ('score_gt', 'SHADOWBALL', 'BODYSLAM')]),
    ('immunity_electric_vs_ground', 0,
     mon('MAGNEZONE', 50, ['THUNDERBOLT', 'FLASHCANNON']),
     mon('GARCHOMP', 50, ['EARTHQUAKE']),
     [('must_not_choose_move', 'THUNDERBOLT'),
      ('score_gt', 'FLASHCANNON', 'THUNDERBOLT')]),

    # --- effectiveness ordering -------------------------------------------
    ('super_effective_preferred', 0,
     mon('MAGNEZONE', 50, ['THUNDERBOLT', 'FLASHCANNON']),
     mon('GYARADOS', 50, ['WATERFALL']),
     [('score_gt', 'THUNDERBOLT', 'FLASHCANNON')]),
    ('resisted_move_deprioritised', 0,
     mon('GARCHOMP', 50, ['DRAGONCLAW', 'EARTHQUAKE']),
     mon('MAGNEZONE', 50, ['THUNDERBOLT']),
     [('score_gt', 'EARTHQUAKE', 'DRAGONCLAW')]),

    # --- switching --------------------------------------------------------
    ('switch_when_outmatched_low_hp', 0,
     mon('ALAKAZAM', 50, ['PSYCHIC'], hp_pct=8),
     mon('GENGAR', 50, ['SHADOWBALL', 'SUCKERPUNCH']),
     [('must_consider_switch',)],
     [mon('SNORLAX', 50, ['BODYSLAM', 'REST'])]),
    ('no_switch_when_winning', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE']),
     mon('MAGNEZONE', 50, ['THUNDERBOLT'], hp_pct=10),
     [('must_not_switch',)],
     [mon('SNORLAX', 50, ['BODYSLAM'])]),
    ('single_mon_cannot_switch', 0,
     mon('ALAKAZAM', 50, ['PSYCHIC'], hp_pct=5),
     mon('GENGAR', 50, ['SHADOWBALL']),
     [('must_not_switch',)]),

    # --- status / setup sanity -------------------------------------------
    ('no_status_on_already_statused', 0,
     mon('GENGAR', 50, ['WILLOWISP', 'SLUDGEBOMB']),
     mon('SNORLAX', 50, ['BODYSLAM'], status='burn'),
     [('must_not_choose_move', 'WILLOWISP')]),
    ('setup_when_safe', 0,
     mon('SNORLAX', 50, ['SWORDSDANCE', 'BODYSLAM'], hp_pct=100),
     mon('MAGNEZONE', 50, ['FLASHCANNON'], hp_pct=100),
     [('must_choose_any',)]),
    ('heal_when_low', 0,
     mon('SNORLAX', 50, ['RECOVER', 'BODYSLAM'], hp_pct=15),
     mon('ALAKAZAM', 50, ['PSYCHIC']),
     [('must_choose_any',)]),

    # --- field awareness (Reborn-specific; field 6 vs no field) -----------
    ('field_changes_scores', 6,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'DRAGONCLAW']),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('must_choose_any',)]),
]

# ---------------------------------------------------------------------------
#  Corpus v2 — scale-up to 60. Every assertion below rests on a mechanic that is
#  true regardless of engine or AI: type immunity, status immunity, redundant status,
#  or a strict effectiveness ordering. Nothing here encodes "what Reborn happened to do".
#
#  Types used (verified against this game's PBS):
#    SKARMORY Steel/Flying   GENGAR Ghost/Poison    GARCHOMP Dragon/Ground
#    SNORLAX Normal          UMBREON Dark           CLEFABLE Fairy
#    FERROTHORN Grass/Steel  TOXAPEX Poison/Water   ARCANINE Fire
#    MAGNEZONE Electric/Steel  GYARADOS Water/Flying  TYRANITAR Rock/Dark
#    FLYGON Ground/Dragon (LEVITATE — its only ability, so the immunity is guaranteed)
# ---------------------------------------------------------------------------
CORPUS_V2 = [
    # --- kill recognition (6) ---------------------------------------------
    # Both EQ and Dragon Claw are lethal at 5% and the AI scores them IDENTICALLY —
    # once a move kills, extra damage adds nothing. So the assertion is "take a kill,
    # do not Protect", not "take this specific kill".
    ('kill_recognised_raises_score', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'DRAGONCLAW', 'PROTECT']),
     mon('MAGNEZONE', 50, ['FLASHCANNON'], hp_pct=5),
     [('must_not_choose_move', 'PROTECT'),
      ('score_gt', 'EARTHQUAKE', 'PROTECT')]),
    ('kill_over_status', 0,
     mon('GENGAR', 50, ['SHADOWBALL', 'WILLOWISP']),
     mon('ALAKAZAM', 50, ['PSYCHIC'], hp_pct=7),
     [('must_not_choose_move', 'WILLOWISP'),
      ('score_gt', 'SHADOWBALL', 'WILLOWISP')]),
    ('kill_over_protect', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'PROTECT']),
     mon('MAGNEZONE', 50, ['FLASHCANNON'], hp_pct=5),
     [('must_not_choose_move', 'PROTECT'),
      ('score_gt', 'EARTHQUAKE', 'PROTECT')]),
    ('kill_over_heal', 0,
     mon('BLISSEY', 50, ['SOFTBOILED', 'DAZZLINGGLEAM'], hp_pct=95),
     mon('TYRANITAR', 50, ['CRUNCH'], hp_pct=4),
     [('score_gt', 'DAZZLINGGLEAM', 'SOFTBOILED')]),
    ('kill_over_substitute', 0,
     mon('GENGAR', 50, ['SHADOWBALL', 'SUBSTITUTE']),
     mon('ALAKAZAM', 50, ['PSYCHIC'], hp_pct=6),
     [('score_gt', 'SHADOWBALL', 'SUBSTITUTE')]),
    ('kill_over_leechseed', 0,
     mon('FERROTHORN', 50, ['POWERWHIP', 'LEECHSEED']),
     mon('STARMIE', 50, ['SURF'], hp_pct=5),
     [('score_gt', 'POWERWHIP', 'LEECHSEED')]),

    # --- type immunity (10) -----------------------------------------------
    ('imm_ground_vs_flying_2', 0,
     mon('FLYGON', 50, ['EARTHQUAKE', 'DRAGONCLAW']),
     mon('SKARMORY', 50, ['BRAVEBIRD']),
     [('must_not_choose_move', 'EARTHQUAKE'), ('score_gt', 'DRAGONCLAW', 'EARTHQUAKE')]),
    ('imm_ground_vs_levitate', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'DRAGONCLAW']),
     mon('FLYGON', 50, ['DRAGONCLAW']),
     [('must_not_choose_move', 'EARTHQUAKE'), ('score_gt', 'DRAGONCLAW', 'EARTHQUAKE')]),
    ('imm_normal_vs_ghost_2', 0,
     mon('SNORLAX', 50, ['BODYSLAM', 'CRUNCH']),
     mon('GENGAR', 50, ['SHADOWBALL']),
     [('must_not_choose_move', 'BODYSLAM'), ('score_gt', 'CRUNCH', 'BODYSLAM')]),
    ('imm_fighting_vs_ghost', 0,
     mon('MACHAMP', 50, ['CLOSECOMBAT', 'CRUNCH']),
     mon('GENGAR', 50, ['SHADOWBALL']),
     [('must_not_choose_move', 'CLOSECOMBAT'), ('score_gt', 'CRUNCH', 'CLOSECOMBAT')]),
    ('imm_ghost_vs_normal', 0,
     mon('GENGAR', 50, ['SHADOWBALL', 'SLUDGEBOMB']),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('must_not_choose_move', 'SHADOWBALL'), ('score_gt', 'SLUDGEBOMB', 'SHADOWBALL')]),
    ('imm_electric_vs_ground_2', 0,
     mon('JOLTEON', 50, ['THUNDERBOLT', 'SHADOWBALL']),
     mon('FLYGON', 50, ['DRAGONCLAW']),
     [('must_not_choose_move', 'THUNDERBOLT'), ('score_gt', 'SHADOWBALL', 'THUNDERBOLT')]),
    ('imm_poison_vs_steel', 0,
     mon('GENGAR', 50, ['SLUDGEBOMB', 'SHADOWBALL']),
     mon('SKARMORY', 50, ['BRAVEBIRD']),
     [('must_not_choose_move', 'SLUDGEBOMB'), ('score_gt', 'SHADOWBALL', 'SLUDGEBOMB')]),
    ('imm_psychic_vs_dark', 0,
     mon('ALAKAZAM', 50, ['PSYCHIC', 'DAZZLINGGLEAM']),
     mon('UMBREON', 50, ['CRUNCH']),
     [('must_not_choose_move', 'PSYCHIC'), ('score_gt', 'DAZZLINGGLEAM', 'PSYCHIC')]),
    ('imm_dragon_vs_fairy', 0,
     mon('DRAGONITE', 50, ['DRAGONCLAW', 'EARTHQUAKE']),
     mon('CLEFABLE', 50, ['MOONBLAST']),
     [('must_not_choose_move', 'DRAGONCLAW'), ('score_gt', 'EARTHQUAKE', 'DRAGONCLAW')]),
    ('imm_ground_vs_flying_gyarados', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'DRAGONCLAW']),
     mon('GYARADOS', 50, ['WATERFALL']),
     [('must_not_choose_move', 'EARTHQUAKE')]),

    # --- effectiveness ordering (10) --------------------------------------
    ('eff_4x_electric_vs_gyarados', 0,
     mon('JOLTEON', 50, ['THUNDERBOLT', 'SHADOWBALL']),
     mon('GYARADOS', 50, ['WATERFALL']),
     [('score_gt', 'THUNDERBOLT', 'SHADOWBALL')]),
    ('eff_4x_fighting_vs_tyranitar', 0,
     mon('MACHAMP', 50, ['CLOSECOMBAT', 'EARTHQUAKE']),
     mon('TYRANITAR', 50, ['CRUNCH']),
     [('score_gt', 'CLOSECOMBAT', 'EARTHQUAKE')]),
    ('eff_water_vs_fire', 0,
     mon('VAPOREON', 50, ['SURF', 'ICEBEAM']),
     mon('ARCANINE', 50, ['FLAMETHROWER']),
     [('score_gt', 'SURF', 'ICEBEAM')]),
    ('eff_fire_vs_steelgrass', 0,
     mon('ARCANINE', 50, ['FLAMETHROWER', 'CRUNCH']),
     mon('FERROTHORN', 50, ['POWERWHIP']),
     [('score_gt', 'FLAMETHROWER', 'CRUNCH')]),
    ('eff_fairy_vs_dragon', 0,
     mon('CLEFABLE', 50, ['MOONBLAST', 'FLAMETHROWER']),
     mon('GARCHOMP', 50, ['EARTHQUAKE']),
     [('score_gt', 'MOONBLAST', 'FLAMETHROWER')]),
    ('eff_ground_vs_electricsteel', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'DRAGONCLAW']),
     mon('MAGNEZONE', 50, ['FLASHCANNON']),
     [('score_gt', 'EARTHQUAKE', 'DRAGONCLAW')]),
    ('eff_poison_vs_fairy', 0,
     mon('WEEZING', 50, ['SLUDGEBOMB', 'FLAMETHROWER']),
     mon('CLEFABLE', 50, ['MOONBLAST']),
     [('score_gt', 'SLUDGEBOMB', 'FLAMETHROWER')]),
    ('eff_ice_vs_dragonground', 0,
     mon('LAPRAS', 50, ['ICEBEAM', 'SURF']),
     mon('GARCHOMP', 50, ['EARTHQUAKE']),
     [('score_gt', 'ICEBEAM', 'SURF')]),
    ('eff_fire_vs_scizor', 0,
     mon('ARCANINE', 50, ['FLAMETHROWER', 'CRUNCH']),
     mon('SCIZOR', 50, ['BULLETPUNCH']),
     [('score_gt', 'FLAMETHROWER', 'CRUNCH')]),
    ('eff_resisted_deprioritised_2', 0,
     mon('DRAGONITE', 50, ['DRAGONCLAW', 'EARTHQUAKE']),
     mon('SKARMORY', 50, ['BRAVEBIRD']),
     [('score_gt', 'DRAGONCLAW', 'EARTHQUAKE')]),

    # --- status immunity (5) ----------------------------------------------
    ('status_burn_vs_fire', 0,
     mon('GENGAR', 50, ['WILLOWISP', 'SHADOWBALL']),
     mon('ARCANINE', 50, ['FLAMETHROWER']),
     [('must_not_choose_move', 'WILLOWISP')]),
    ('status_toxic_vs_steel', 0,
     mon('GENGAR', 50, ['TOXIC', 'SHADOWBALL']),
     mon('SKARMORY', 50, ['BRAVEBIRD']),
     [('must_not_choose_move', 'TOXIC')]),
    ('status_toxic_vs_poison', 0,
     mon('GENGAR', 50, ['TOXIC', 'SHADOWBALL']),
     mon('TOXAPEX', 50, ['SCALD']),
     [('must_not_choose_move', 'TOXIC')]),
    ('status_thunderwave_vs_ground', 0,
     mon('JOLTEON', 50, ['THUNDERWAVE', 'SHADOWBALL']),
     mon('FLYGON', 50, ['DRAGONCLAW']),
     [('must_not_choose_move', 'THUNDERWAVE')]),
    ('status_spore_vs_grass', 0,
     mon('BRELOOM', 50, ['SPORE', 'CLOSECOMBAT']),
     mon('FERROTHORN', 50, ['POWERWHIP']),
     [('must_not_choose_move', 'SPORE')]),

    # --- redundant status (5) ---------------------------------------------
    ('redundant_burn', 0,
     mon('GENGAR', 50, ['WILLOWISP', 'SLUDGEBOMB']),
     mon('SNORLAX', 50, ['BODYSLAM'], status='burn'),
     [('must_not_choose_move', 'WILLOWISP')]),
    ('redundant_toxic', 0,
     mon('GENGAR', 50, ['TOXIC', 'SLUDGEBOMB']),
     mon('SNORLAX', 50, ['BODYSLAM'], status='poison'),
     [('must_not_choose_move', 'TOXIC')]),
    ('redundant_sleep', 0,
     mon('GENGAR', 50, ['HYPNOSIS', 'SLUDGEBOMB']),
     mon('SNORLAX', 50, ['BODYSLAM'], status='sleep'),
     [('must_not_choose_move', 'HYPNOSIS')]),
    ('redundant_paralysis', 0,
     mon('JOLTEON', 50, ['THUNDERWAVE', 'THUNDERBOLT']),
     mon('SNORLAX', 50, ['BODYSLAM'], status='paralysis'),
     [('must_not_choose_move', 'THUNDERWAVE')]),
    ('redundant_burn_on_low_hp_target', 0,
     mon('GENGAR', 50, ['WILLOWISP', 'SLUDGEBOMB']),
     mon('SNORLAX', 50, ['BODYSLAM'], status='burn', hp_pct=10),
     [('must_not_choose_move', 'WILLOWISP')]),

    # --- setup / healing (8) ----------------------------------------------
    ('setup_vs_harmless', 0,
     mon('SNORLAX', 50, ['SWORDSDANCE', 'BODYSLAM']),
     mon('GENGAR', 50, ['WILLOWISP'], hp_pct=100),
     [('must_choose_any',)]),
    ('no_setup_at_max_stage', 0,
     mon('GARCHOMP', 50, ['SWORDSDANCE', 'EARTHQUAKE'], stages={'atk': 6}),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('must_not_choose_move', 'SWORDSDANCE')]),
    ('no_calmmind_at_max_stage', 0,
     mon('ALAKAZAM', 50, ['CALMMIND', 'PSYCHIC'], stages={'spa': 6, 'spd': 6}),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('must_not_choose_move', 'CALMMIND')]),
    # 24%, not 12%. Measured on the reference, Alakazam's Psychic does 18.8% to this
    # Blissey, which at 12% HP kills it on every damage roll (85-100%) before a slower
    # Blissey can act — so the card was asserting that healing into certain death is
    # correct, and stock Reborn passed it only through the recovercode blind spot this
    # corpus is meant to catch (it never checks whether it moves first). At 24% the
    # heal is what the card always meant: low, threatened, and worth taking.
    ('heal_at_low_hp', 0,
     mon('BLISSEY', 50, ['SOFTBOILED', 'DAZZLINGGLEAM'], hp_pct=24),
     mon('ALAKAZAM', 50, ['PSYCHIC']),
     [('score_gt', 'SOFTBOILED', 'DAZZLINGGLEAM')]),
    ('no_heal_at_full_hp', 0,
     mon('BLISSEY', 50, ['SOFTBOILED', 'DAZZLINGGLEAM'], hp_pct=100),
     mon('ALAKAZAM', 50, ['PSYCHIC']),
     [('must_not_choose_move', 'SOFTBOILED')]),
    ('no_recover_at_full_hp', 0,
     mon('STARMIE', 50, ['RECOVER', 'SURF'], hp_pct=100),
     mon('ARCANINE', 50, ['FLAMETHROWER']),
     [('must_not_choose_move', 'RECOVER')]),
    ('no_roost_at_full_hp', 0,
     mon('SKARMORY', 50, ['ROOST', 'BRAVEBIRD'], hp_pct=100),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('must_not_choose_move', 'ROOST')]),
    ('heal_beats_weak_attack', 0,
     mon('SKARMORY', 50, ['ROOST', 'BRAVEBIRD'], hp_pct=30),
     mon('FERROTHORN', 50, ['POWERWHIP']),
     [('score_gt', 'ROOST', 'BRAVEBIRD')]),

    # --- switching (6) ----------------------------------------------------
    ('switch_considered_when_crippled', 0,
     mon('MAGNEZONE', 50, ['FLASHCANNON'], hp_pct=6,
         stages={'atk': -6, 'spa': -6}),
     mon('GARCHOMP', 50, ['EARTHQUAKE']),
     [('must_consider_switch',)],
     [mon('FLYGON', 50, ['DRAGONCLAW'])]),
    ('switch_considered_stat_crushed', 0,
     mon('SNORLAX', 50, ['BODYSLAM'], stages={'atk': -6}),
     mon('MACHAMP', 50, ['CLOSECOMBAT']),
     [('must_consider_switch',)],
     [mon('GENGAR', 50, ['SHADOWBALL'])]),
    ('no_switch_when_healthy_winning', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE']),
     mon('MAGNEZONE', 50, ['FLASHCANNON'], hp_pct=8),
     [('must_not_switch',)],
     [mon('SNORLAX', 50, ['BODYSLAM'])]),
    ('no_switch_single_mon_low', 0,
     mon('MAGNEZONE', 50, ['FLASHCANNON'], hp_pct=4),
     mon('GARCHOMP', 50, ['EARTHQUAKE']),
     [('must_not_switch',)]),
    ('no_switch_full_hp_neutral', 0,
     mon('SNORLAX', 50, ['BODYSLAM']),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('must_not_switch',)],
     [mon('GENGAR', 50, ['SHADOWBALL'])]),
    ('switch_eval_runs_with_bench', 0,
     mon('ALAKAZAM', 50, ['PSYCHIC'], hp_pct=15),
     mon('UMBREON', 50, ['CRUNCH']),
     [('must_consider_switch',)],
     [mon('SNORLAX', 50, ['BODYSLAM'])]),

    # --- field sensitivity (4) --------------------------------------------
    ('field_1_scores_produced', 1,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'DRAGONCLAW']),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('must_choose_any',)]),
    ('field_2_scores_produced', 2,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'DRAGONCLAW']),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('must_choose_any',)]),
    ('field_immunity_still_holds', 6,
     mon('SNORLAX', 50, ['BODYSLAM', 'CRUNCH']),
     mon('GENGAR', 50, ['SHADOWBALL']),
     [('must_not_choose_move', 'BODYSLAM')]),
    ('field_kill_still_recognised', 6,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'PROTECT']),
     mon('MAGNEZONE', 50, ['FLASHCANNON'], hp_pct=5),
     [('must_not_choose_move', 'PROTECT'),
      ('score_gt', 'EARTHQUAKE', 'PROTECT')]),

    # --- forced switches (3) ----------------------------------------------
    # chooseAction:1577 needs BOTH: shouldswitchscore > best move score, AND
    # switchscore.max > 100. Earlier attempts stalled at 98.7 because the bench mon was
    # merely "fine". These give the AI a genuinely great pivot — a type immunity to the
    # attack it is facing — while crippling the active mon's offence with -6 stages.
    # HP is kept above 30%: shouldSwitch? subtracts 100 below that (PokeBattle_AI_2:13378).
    ('switch_forced_snorlax_to_ghost', 0,
     mon('SNORLAX', 50, ['BODYSLAM'], hp_pct=60, stages={'atk': -6}),
     mon('MACHAMP', 50, ['CLOSECOMBAT']),
     [('must_switch',)],
     [mon('GENGAR', 50, ['SHADOWBALL', 'SLUDGEBOMB'])]),
    # NOTE: a Levitate pivot into Garchomp does NOT work, and the reason is instructive.
    # When the AI has no known damaging move for the foe it invents an 80-BP STAB move of
    # the foe's type (PokeBattle_Move_FFF, PokeBattle_AI_2.rb:17454). Against Garchomp it
    # therefore assumes a DRAGON attack, and Flygon is 2x weak to Dragon — so Flygon
    # scored -300 as a switch-in despite being Ground-immune. The AI hedges against unseen
    # moves rather than assuming the foe only has what it has shown. Pick a pivot that is
    # safe against the opponent's STAB TYPES, not just its known moves.
    # Documented NEAR-MISS, kept deliberately. Same shape as the two above but the foe
    # (Normal STAB) is a milder threat, so the Ghost pivot scores 93.8 — just under the
    # switchscore.max > 100 gate at chooseAction:1577 — and the AI attacks instead
    # (sss=100). It shows the switch threshold is tight, and that "wants to switch" and
    # "switches" are two different bars. Assert only the weaker property.
    ('switch_wanted_but_pivot_below_gate', 0,
     mon('SNORLAX', 50, ['BODYSLAM'], hp_pct=60, stages={'atk': -6}),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('must_consider_switch',)],
     [mon('GENGAR', 50, ['SHADOWBALL', 'SLUDGEBOMB'])]),
    ('switch_forced_tyranitar_to_ghost', 0,
     mon('TYRANITAR', 50, ['CRUNCH'], hp_pct=55, stages={'atk': -6, 'def': -4}),
     mon('MACHAMP', 50, ['CLOSECOMBAT']),
     [('must_switch',)],
     [mon('GENGAR', 50, ['SHADOWBALL', 'SLUDGEBOMB'])]),

    # --- misc sanity (1) --------------------------------------------------
    ('no_useless_move_vs_immune_only_option', 0,
     mon('SNORLAX', 50, ['BODYSLAM', 'EARTHQUAKE', 'CRUNCH']),
     mon('GENGAR', 50, ['SHADOWBALL']),
     [('must_not_choose_move', 'BODYSLAM')]),
]

# ---------------------------------------------------------------------------
#  Corpus v3 — Batch A (2026-09-03). Three new families, all single-decision:
#
#  * Absorbing abilities — the same class of hard immunity as types (Gen 3's own
#    AI_CheckBadMove treats Volt/Water Absorb, Flash Fire and Levitate identically:
#    pret battle_ai_scripts.s Score_Minus12). Targets here have TWO possible PBS
#    abilities, so the relevant one is PINNED via ability= — an unpinned target rolls
#    its slot from personalID and the assertion becomes a coin flip on mon generation.
#  * Move-fails-mechanically — Belly Drum below 50% HP, Substitute below 25%, Dream
#    Eater on an awake target, Explosion into a Normal-immune, Rest at full HP. Using
#    one of these is strictly wasted; engine-neutral by rulebook.
#  * Role decisions (staller/phazer/setup timing/counter-coverage) — universal
#    properties a wall/staller kit must satisfy, phrased as orderings so they do not
#    encode any one AI's magnitudes. These mons carry full 4-move REAL kits on
#    purpose: pad_to_four no-ops, and PBAI mints the intended role instead of the
#    neutral :PHYSICALBREAKER filler role — roles become the measured variable.
# ---------------------------------------------------------------------------
CORPUS_V3 = [
    # --- absorbing abilities (3) ------------------------------------------
    ('absorb_water_vs_waterabsorb', 0,
     mon('GYARADOS', 50, ['WATERFALL', 'CRUNCH']),
     mon('VAPOREON', 50, ['SURF'], ability='WATERABSORB'),
     [('must_not_choose_move', 'WATERFALL'),
      ('score_gt', 'CRUNCH', 'WATERFALL')]),
    ('absorb_electric_vs_voltabsorb', 0,
     mon('MAGNEZONE', 50, ['THUNDERBOLT', 'FLASHCANNON']),
     mon('JOLTEON', 50, ['THUNDERBOLT'], ability='VOLTABSORB'),
     [('must_not_choose_move', 'THUNDERBOLT'),
      ('score_gt', 'FLASHCANNON', 'THUNDERBOLT')]),
    ('absorb_fire_vs_flashfire', 0,
     mon('ARCANINE', 50, ['FLAMETHROWER', 'CRUNCH']),
     mon('FLAREON', 50, ['FLAMETHROWER'], ability='FLASHFIRE'),
     [('must_not_choose_move', 'FLAMETHROWER'),
      ('score_gt', 'CRUNCH', 'FLAMETHROWER')]),

    # --- move fails mechanically (5) --------------------------------------
    ('fail_bellydrum_below_half', 0,
     mon('SNORLAX', 50, ['BELLYDRUM', 'BODYSLAM'], hp_pct=40),
     mon('ARCANINE', 50, ['FLAMETHROWER']),
     [('must_not_choose_move', 'BELLYDRUM')]),
    ('fail_substitute_below_quarter', 0,
     mon('GENGAR', 50, ['SUBSTITUTE', 'SLUDGEBOMB'], hp_pct=20),
     mon('CLEFABLE', 50, ['MOONBLAST']),
     [('must_not_choose_move', 'SUBSTITUTE')]),
    ('fail_dreameater_awake', 0,
     mon('GENGAR', 50, ['DREAMEATER', 'SHADOWBALL']),
     mon('ALAKAZAM', 50, ['PSYCHIC']),
     [('must_not_choose_move', 'DREAMEATER'),
      ('score_gt', 'SHADOWBALL', 'DREAMEATER')]),
    ('fail_explosion_vs_ghost', 0,
     mon('GOLEM', 50, ['EXPLOSION', 'ROCKSLIDE']),
     mon('GENGAR', 50, ['SHADOWBALL']),
     [('must_not_choose_move', 'EXPLOSION'),
      ('score_gt', 'ROCKSLIDE', 'EXPLOSION')]),
    ('fail_rest_at_full_hp', 0,
     mon('SNORLAX', 50, ['REST', 'BODYSLAM'], hp_pct=100),
     mon('ARCANINE', 50, ['FLAMETHROWER']),
     [('must_not_choose_move', 'REST')]),

    # --- redundant debuff (1) ---------------------------------------------
    ('redundant_debuff_at_min', 0,
     mon('CLEFABLE', 50, ['CHARM', 'MOONBLAST']),
     mon('MACHAMP', 50, ['CLOSECOMBAT'], stages={'atk': -6}),
     [('must_not_choose_move', 'CHARM')]),

    # --- priority awareness (1) -------------------------------------------
    # AI is slower (Azumarill 50 Spe vs Gengar 110) and dies to the known Shadow Ball;
    # the foe is in range of BOTH its moves. Only Aqua Jet's +1 priority converts the
    # position — Play Rough kills a target that has already moved. VERIFY ON REFERENCE
    # FIRST: if the engine scores all lethal moves identically (the documented
    # no-overkill-ranking behaviour), this ordering cannot hold and the assertion —
    # not the AI — is what needs revisiting (weaken to must_choose_any + note).
    ('priority_secures_kill_when_slower', 0,
     mon('AZUMARILL', 50, ['AQUAJET', 'PLAYROUGH'], hp_pct=20),
     mon('GENGAR', 50, ['SHADOWBALL'], hp_pct=5),
     [('score_gt', 'AQUAJET', 'PLAYROUGH')]),

    # --- role decisions: staller / phazer / setup timing / coverage (5) ---
    ('staller_toxic_the_wall', 0,
     mon('TOXAPEX', 50, ['TOXIC', 'SCALD', 'RECOVER', 'HAZE']),
     mon('SUICUNE', 50, ['SURF'], hp_pct=100),
     [('score_gt', 'TOXIC', 'SCALD')]),
    ('phazer_haze_vs_setup', 0,
     mon('TOXAPEX', 50, ['HAZE', 'SCALD', 'RECOVER', 'TOXIC']),
     mon('GYARADOS', 50, ['WATERFALL'], stages={'atk': 6}),
     [('score_gt', 'HAZE', 'SCALD')]),
    ('no_haze_unboosted', 0,
     mon('TOXAPEX', 50, ['HAZE', 'SCALD', 'RECOVER', 'TOXIC']),
     mon('MACHAMP', 50, ['CLOSECOMBAT']),
     [('score_gt', 'SCALD', 'HAZE')]),
    # Contrast with lethal_vs_healthy_target_may_setup: setting up is fine when safe,
    # throwing when the foe's known move kills you first. Starmie's Ice Beam is 4x
    # into Garchomp at 8%.
    ('setup_futile_at_low_hp_vs_threat', 0,
     mon('GARCHOMP', 50, ['SWORDSDANCE', 'EARTHQUAKE'], hp_pct=8),
     mon('STARMIE', 50, ['ICEBEAM']),
     [('must_not_choose_move', 'SWORDSDANCE')]),
    ('counter_useless_vs_special_attacker', 0,
     mon('SNORLAX', 50, ['COUNTER', 'BODYSLAM']),
     mon('ALAKAZAM', 50, ['PSYCHIC']),
     [('must_not_choose_move', 'COUNTER'),
      ('score_gt', 'BODYSLAM', 'COUNTER')]),
]

# ---------------------------------------------------------------------------
#  Corpus v4 — Batch B (2026-09-03): scenarios needing battle-level state that
#  mons cannot carry — side effects (hazards/screens) and weather. Both engines
#  store these identically (PBEffects on ActiveSide; PBAI's AI_Side#effects
#  delegates to battle.sides[n].effects, 01_AI_Main.rb:3037), so one probe key
#  serves both. Scenario entries gain an optional trailing dict:
#    {'weather': 'rain', 'ai_side': {...}, 'player_side': {...}}
#  where player_side = the PLAYER's half of the field (where hazards the AI lays
#  accumulate) and ai_side = the AI's half (its own screens).
#
#  Every redundancy below is a hard rulebook fact — a 4th Spikes layer, 3rd Toxic
#  Spikes, second Stealth Rock/Reflect/Light Screen and a weather move into the
#  same weather all FAIL outright — so "don't pick it over a working attack" is
#  engine-neutral. Both AIs claim to know this (Reborn miniscore*=0 at
#  PokeBattle_AI_2.rb:4619/4655/4680, raincode:8195, suncode:8172, screens:6973;
#  PBAI score=0 at 02_AI_Score.rb:816-822, Reflect:1344); the corpus makes it
#  measured instead of read.
# ---------------------------------------------------------------------------
CORPUS_V4 = [
    # --- redundant hazards (3) --------------------------------------------
    ('redundant_spikes_at_max', 0,
     mon('SKARMORY', 50, ['SPIKES', 'BRAVEBIRD']),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('must_not_choose_move', 'SPIKES'),
      ('score_gt', 'BRAVEBIRD', 'SPIKES')],
     {'player_side': {'spikes': 3}}),
    ('redundant_toxicspikes_at_max', 0,
     mon('TOXAPEX', 50, ['TOXICSPIKES', 'SCALD']),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('must_not_choose_move', 'TOXICSPIKES'),
      ('score_gt', 'SCALD', 'TOXICSPIKES')],
     {'player_side': {'toxicspikes': 2}}),
    ('redundant_stealthrock', 0,
     mon('FERROTHORN', 50, ['STEALTHROCK', 'POWERWHIP']),
     mon('STARMIE', 50, ['SURF']),
     [('must_not_choose_move', 'STEALTHROCK'),
      ('score_gt', 'POWERWHIP', 'STEALTHROCK')],
     {'player_side': {'stealthrock': 1}}),

    # --- redundant screens (2) --------------------------------------------
    # Screens live on the AI's OWN side; the foe is the matching attack category
    # so the screen would be attractive if it were not already up.
    ('redundant_reflect', 0,
     mon('CLEFABLE', 50, ['REFLECT', 'MOONBLAST']),
     mon('MACHAMP', 50, ['CLOSECOMBAT']),
     [('must_not_choose_move', 'REFLECT'),
      ('score_gt', 'MOONBLAST', 'REFLECT')],
     {'ai_side': {'reflect': 5}}),
    ('redundant_lightscreen', 0,
     mon('CLEFABLE', 50, ['LIGHTSCREEN', 'MOONBLAST']),
     mon('ALAKAZAM', 50, ['PSYCHIC']),
     [('must_not_choose_move', 'LIGHTSCREEN'),
      ('score_gt', 'MOONBLAST', 'LIGHTSCREEN')],
     {'ai_side': {'lightscreen': 5}}),

    # --- redundant weather (2) --------------------------------------------
    ('redundant_raindance_in_rain', 0,
     mon('POLITOED', 50, ['RAINDANCE', 'SURF']),
     mon('ARCANINE', 50, ['FLAMETHROWER']),
     [('must_not_choose_move', 'RAINDANCE'),
      ('score_gt', 'SURF', 'RAINDANCE')],
     {'weather': 'rain'}),
    ('redundant_sunnyday_in_sun', 0,
     mon('CHARIZARD', 50, ['SUNNYDAY', 'FLAMETHROWER']),
     mon('FERROTHORN', 50, ['POWERWHIP']),
     [('must_not_choose_move', 'SUNNYDAY'),
      ('score_gt', 'FLAMETHROWER', 'SUNNYDAY')],
     {'weather': 'sun'}),

    # --- weather-dependent move quality (4) -------------------------------
    # Same mon, same moves, weather flipped: the ordering must invert. Both
    # halves target expected damage — 110 BP at 70% (=77) loses to 90 BP sure
    # damage, and never-miss 110 in rain beats it (Reborn treats Thunder as
    # 100-acc in rain, PokeBattle_AI_2.rb:9979). VERIFY ON REFERENCE FIRST:
    # if the reference does not weight accuracy into move scores, the no-rain
    # half cannot hold — weaken THAT half to must_choose_any + note, keep the
    # rain half (never-miss is modelled explicitly, see nevermisscode:3478).
    ('thunder_shaky_without_rain', 0,
     mon('JOLTEON', 50, ['THUNDER', 'THUNDERBOLT']),
     mon('GYARADOS', 50, ['WATERFALL']),
     [('score_gt', 'THUNDERBOLT', 'THUNDER')]),
    ('thunder_sure_in_rain', 0,
     mon('JOLTEON', 50, ['THUNDER', 'THUNDERBOLT']),
     mon('GYARADOS', 50, ['WATERFALL']),
     [('score_gt', 'THUNDER', 'THUNDERBOLT')],
     {'weather': 'rain'}),
    # Solar Beam outside sun spends a turn charging (≈half throughput, and the
    # charge turn is free damage for the foe); in sun it fires instantly at
    # 120 BP vs Energy Ball's 90. Target is 4x grass-weak so both are live.
    ('solarbeam_bad_outside_sun', 0,
     mon('VENUSAUR', 50, ['SOLARBEAM', 'ENERGYBALL']),
     mon('SWAMPERT', 50, ['EARTHQUAKE']),
     [('score_gt', 'ENERGYBALL', 'SOLARBEAM')]),
    # score_gte, not score_gt: on the reference both 4x grass moves land in the
    # same capped score band in sun (110 = 110) — the engine does not rank
    # overkill, so a strict ordering cannot hold. The property that CAN hold is
    # "sun must erase Solar Beam's charge-turn penalty" — i.e. it must no longer
    # be worse (contrast solarbeam_bad_outside_sun, where strict < is required).
    ('solarbeam_good_in_sun', 0,
     mon('VENUSAUR', 50, ['SOLARBEAM', 'ENERGYBALL']),
     mon('SWAMPERT', 50, ['EARTHQUAKE']),
     [('score_gte', 'SOLARBEAM', 'ENERGYBALL')],
     {'weather': 'sun'}),
]

# ---------------------------------------------------------------------------
#  Corpus v5 — switching, second pass (2026-09-03). Grounded in a full read of
#  both switch systems:
#
#  Reborn shouldSwitch? (PokeBattle_AI_2.rb:13344) = pro − anti, gated at
#  chooseAction:1577 on BOTH `sss > best move score` AND `switchscore.max > 100`
#  (+ shouldHardSwitch?). Pro: all-moves-immune +140, negative stages 25-30/stage,
#  foe-just-switched-in-would-OHKO +185 (needs foe turncount==0 — always true in
#  the probe — and own HP > 40%), statuses/Leech Seed/Perish (effects, not yet
#  settable). Anti: own boosts 15-30/stage, OWN-SIDE HAZARDS 15/layer (:13655),
#  pivot-move-in-kit +150, fresh-mon turncount bonus +50. Switch-in quality also
#  charges candidates hazard damage against effective HP (:11829). Calibration
#  from today's reference: the forced-switch pivot scores 104.3 vs the >100 gate
#  — a 4.3 margin — so hazards flip it through both mechanisms at once.
#
#  PBAI (01_AI_Main.rb:1276): switching is SKIPPED outright when the AI has a
#  killing move; ai_should_switch? compares small-int SwitchHandler triggers
#  against the best move score, with a live rand(2) on ties (:1755 — unlike the
#  dead move tie-break). It has a "don't switch while set up" handler
#  (04_AI_Switch.rb:275), so no_switch_when_set_up is cross-AI testable.
#
#  must_switch assertions follow the verify-on-reference-first protocol: if the
#  reference declines, inspect sss/switchscore in the record and downgrade with
#  a documented reason (the switch_wanted_but_pivot_below_gate precedent).
# ---------------------------------------------------------------------------
CORPUS_V5 = [
    # All four damaging moves are Normal into a Ghost: bothimmune +140, and every
    # move scores 0 so staying in achieves nothing. Four REAL moves so
    # pad_to_four cannot smuggle in LICK (Ghost) or PECK (Flying), which would
    # break the immunity wall. Umbreon resists Gengar's whole STAB set and
    # Crunch is super-effective — a genuinely great pivot.
    ('switch_out_all_moves_immune', 0,
     mon('SNORLAX', 50, ['BODYSLAM', 'DOUBLEEDGE', 'QUICKATTACK', 'HYPERBEAM']),
     mon('GENGAR', 50, ['SHADOWBALL']),
     [('must_switch',)],
     [mon('UMBREON', 50, ['CRUNCH'])]),

    # PAIRED with switch_forced_snorlax_to_ghost: identical position, but the
    # AI's own side now carries max Spikes + Stealth Rock. MEASURED RESULT
    # (reference): sss collapses 325 -> 65 (hazardantiscore + hazard-KO terms),
    # but 65 still beats the crippled mon's best move score (7) and the pivot's
    # switch-in score is UNCHANGED at 104.3 — the :11829 hazard charge feeds a
    # survival check, not the score, and Gengar survives the ~37% chip. So the
    # reference switches anyway — which is defensible play (Snorlax at -6 does
    # nothing forever; 37% on entry is a price worth paying). must_not_switch
    # was therefore an unjustified claim; the pair's value is the measured
    # deterrence delta, so the scenario documents rather than constrains.
    ('switch_stay_hazards_deter', 0,
     mon('SNORLAX', 50, ['BODYSLAM'], hp_pct=60, stages={'atk': -6}),
     mon('MACHAMP', 50, ['CLOSECOMBAT']),
     [('must_choose_any',)],
     [mon('GENGAR', 50, ['SHADOWBALL', 'SLUDGEBOMB'])],
     {'ai_side': {'spikes': 3, 'stealthrock': 1}}),

    # A boosted sweeper mid-snowball must not throw its boosts away. Both AIs
    # claim this: Reborn statantiscore (+30/stage as SWEEPER), PBAI's
    # set-up switch-out handler.
    ('no_switch_when_set_up', 0,
     mon('GYARADOS', 50, ['DRAGONDANCE', 'WATERFALL', 'EARTHQUAKE', 'ICEFANG'],
         stages={'atk': 2, 'spe': 2}),
     mon('SUICUNE', 50, ['SURF']),
     [('must_not_switch',)],
     [mon('SNORLAX', 50, ['BODYSLAM'])]),

    # Foe's shown move OHKOs (Ice Beam 4x into Garchomp) and the foe reads as a
    # fresh counter-switch (turncount 0, own HP > 40%): Reborn's +185
    # counter-switch term plus ±20 type terms. Empoleon quarters Ice Beam.
    ('switch_out_vs_fresh_ohko_counter', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'DRAGONCLAW']),
     mon('LAPRAS', 50, ['ICEBEAM']),
     [('must_switch',)],
     [mon('EMPOLEON', 50, ['SURF', 'FLASHCANNON'])]),

    # Same +185 family, but the pivot's value is an ABILITY immunity, not a type
    # resistance: Volt Absorb Jolteon blanks the only shown move AND the foe's
    # STAB. Ability-aware switch-in valuation only became measurable after the
    # nil-ability harness fix (SIM-SPEC 9.6) — before it, every pivot was
    # ability-less. Gyarados at full HP dies to Thunderbolt (4x). First draft
    # gave Gyarados EARTHQUAKE (4x back into Magnezone, scored 110) and the
    # reference correctly stayed in to kill first — the position, not the AI,
    # was wrong. Both moves here are resisted (0.25/0.5) so staying achieves
    # little and the pivot is the play.
    #
    # Documented NEAR-MISS #2 (same shape as switch_wanted_but_pivot_below_gate):
    # the reference WANTS out — sss 135 vs best move 40 — but Jolteon's
    # switch-in score is 63.7, under the >100 gate. The FFF hedge assumes
    # Magnezone's unshown STEEL STAB (PokeBattle_Move_FFF), which Jolteon takes
    # neutrally, so an ability immunity to everything actually shown does not
    # carry the pivot past the gate. Ability immunity is measurably worth less
    # than a type resistance here (compare Empoleon's 142.1 in the Lapras
    # scenario). Assert only the weaker property.
    ('switch_out_to_absorb_pivot', 0,
     mon('GYARADOS', 50, ['WATERFALL', 'ICEFANG']),
     mon('MAGNEZONE', 50, ['THUNDERBOLT']),
     [('must_consider_switch',)],
     [mon('JOLTEON', 50, ['THUNDERBOLT', 'SHADOWBALL'], ability='VOLTABSORB')]),
]

# ---------------------------------------------------------------------------
#  Corpus v6 — party awareness (2026-09-03). Scenarios where the right choice
#  depends on a BENCH — the AI's own or the player's — not on the two active
#  mons. New machinery: the extra dict accepts 'player_bench': [mon(...), ...]
#  (player bench mons are NOT padded, same convention as the player active:
#  their movesets are the AI's threat model), and bench mons now honour
#  hp_pct — including hp_pct=0 for a fainted bench.
#
#  Code these rest on (all verified, both engines read the party for these):
#  * Reborn phasecode:7916 returns 0 when the target has no bench (Roar has
#    nothing to drag in) and scales 1.2^Spikes/1.3 SR on the TARGET's side.
#    PBAI's phaze handler (02_AI_Score.rb:1042) checks neither.
#  * Reborn pivotcode:7934 zeroes Baton Pass (0 BP) with no own bench. PBAI's
#    pivot branch only reads can_switch? for a +1 role bonus.
#  * Reborn Spikes/Toxic Spikes scoring loops the PLAYER party and multiplies
#    by 0 when no member can be hurt (airborne / steel / poison / boots,
#    :4600-4671). PBAI's hazard handler counts party SIZE only — and subtracts
#    its OWN side's faint count from the OPPONENT's party size (:824-828, a
#    cross-side bug).
#  * Reborn shouldSwitch?:13346 returns -1000 when only one mon is ABLE;
#    PBAI's ai_should_switch? counts non-fainted party the same way.
# ---------------------------------------------------------------------------
CORPUS_V6 = [
    # Phazing needs something to phaze IN. Against a benchless player, Roar/
    # Whirlwind does nothing at all.
    ('roar_useless_vs_last_mon', 0,
     mon('SKARMORY', 50, ['WHIRLWIND', 'BRAVEBIRD']),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('must_not_choose_move', 'WHIRLWIND'),
      ('score_gt', 'BRAVEBIRD', 'WHIRLWIND')]),

    # The inverse: a +6 foe, a real player bench to drag in, and three layers
    # of Spikes + rocks waiting on the player's side. phasecode multiplies
    # ~3.4x for the boosts and ~2.2x for the hazards. VERIFY ON REFERENCE
    # FIRST: the ordering vs a 120 BP STAB attack depends on base-score
    # magnitudes; if the reference prefers the attack, weaken to
    # must_choose_any and document the recorded scores.
    ('phaze_boosted_foe_into_hazards', 0,
     mon('SKARMORY', 50, ['WHIRLWIND', 'BRAVEBIRD']),
     mon('GYARADOS', 50, ['WATERFALL'], stages={'atk': 6}),
     [('score_gt', 'WHIRLWIND', 'BRAVEBIRD')],
     {'player_side': {'spikes': 3, 'stealthrock': 1},
      'player_bench': [mon('SNORLAX', 50, ['BODYSLAM']),
                       mon('MACHAMP', 50, ['CLOSECOMBAT'])]}),

    # Baton Pass with nothing to pass to is a wasted turn (0 BP, no switch
    # target). Reborn pivotcode returns 0; a competent AI must attack instead.
    ('batonpass_useless_no_bench', 0,
     mon('JOLTEON', 50, ['BATONPASS', 'THUNDERBOLT']),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('must_not_choose_move', 'BATONPASS'),
      ('score_gt', 'THUNDERBOLT', 'BATONPASS')]),

    # Spikes into a team that never touches the ground: active Crobat, bench
    # Gyarados + Flygon (Levitate is Flygon's only ability, pinned slot 0 by
    # default). Zero grounded targets -> the layer can never deal damage.
    ('spikes_useless_vs_airborne_team', 0,
     mon('SKARMORY', 50, ['SPIKES', 'BRAVEBIRD']),
     mon('CROBAT', 50, ['CROSSPOISON']),
     [('must_not_choose_move', 'SPIKES'),
      ('score_gt', 'BRAVEBIRD', 'SPIKES')],
     {'player_bench': [mon('GYARADOS', 50, ['WATERFALL']),
                       mon('FLYGON', 50, ['DRAGONCLAW'])]}),

    # Toxic Spikes into a team with no poisonable grounded member: Gengar
    # (Poison type), Magnezone (Steel), Skarmory (Steel + airborne).
    ('toxicspikes_useless_vs_immune_team', 0,
     mon('TOXAPEX', 50, ['TOXICSPIKES', 'SCALD']),
     mon('GENGAR', 50, ['SHADOWBALL']),
     [('must_not_choose_move', 'TOXICSPIKES'),
      ('score_gt', 'SCALD', 'TOXICSPIKES')],
     {'player_bench': [mon('MAGNEZONE', 50, ['THUNDERBOLT']),
                       mon('SKARMORY', 50, ['BRAVEBIRD'])]}),

    # The forced-switch position (sss 325, pivot 104.3 — the reference
    # switches) with the one change that the pivot is DEAD. A fainted bench is
    # no bench: the AI must stay in. Exercises the new bench hp_pct=0 support
    # end to end — if the faint failed to apply, the reference would switch and
    # fail this, so the assertion also guards the probe extension.
    ('no_switch_bench_all_fainted', 0,
     mon('SNORLAX', 50, ['BODYSLAM'], hp_pct=60, stages={'atk': -6}),
     mon('MACHAMP', 50, ['CLOSECOMBAT']),
     [('must_not_switch',)],
     [mon('GENGAR', 50, ['SHADOWBALL', 'SLUDGEBOMB'], hp_pct=0)]),
]

# ---------------------------------------------------------------------------
#  Corpus v7 — effects-driven switching (2026-09-03). The strongest switch
#  triggers in Reborn's shouldSwitch? live in battler EFFECTS the probe could
#  not previously set: Perish Song 1 = +220 (its single biggest term), choice-
#  locked into a dead move = up to +480 cumulative (:13470-13509), no PP = +200,
#  Yawn +95, Leech Seed +65, Toxic counter ×15/turn. New mon keys: effects=
#  {name: value} and pp_all= (see EFFECT_NAMES).
#
#  PBAI comparison points, verified in 04_AI_Switch.rb: its Perish trigger is
#  +20 (:524) — 10x its usual +2/+3 — making the perish scenario the one corpus
#  position where PBAI may genuinely switch; its Toxic trigger is +2 (:292).
#
#  must_switch entries follow verify-on-reference-first with a documented
#  downgrade path. The yawn and chip-stack entries are DELIBERATE doc
#  scenarios (must_choose_any): their triggers (+95, +65+60) sit below the
#  fresh-mon anti term + typical move scores, so what they contribute is the
#  recorded sss delta against the structurally identical perish scenario —
#  a measured ranking of trigger strengths, not a constraint.
# ---------------------------------------------------------------------------
CORPUS_V7 = [
    # Perish count 1: switching clears the counter, staying dies at end of
    # turn. Ferrothorn quarters the only shown move (the Empoleon lesson: type
    # resistance, not ability immunity, is what clears the >100 pivot gate).
    ('switch_out_perish_final_turn', 0,
     mon('SNORLAX', 50, ['BODYSLAM'], effects={'perishsong': 1}),
     mon('SUICUNE', 50, ['SURF']),
     [('must_switch',)],
     [mon('FERROTHORN', 50, ['POWERWHIP', 'GYROBALL'])]),

    # Choice-locked into a move the foe is immune to: every turn spent in is a
    # wasted turn. Thunderbolt scores 0 into a Ground type, so Reborn's
    # cumulative forcedscore reaches +480. Skarmory blanks EQ and resists the
    # Dragon STAB hedge.
    ('switch_out_choice_locked_immune', 0,
     mon('JOLTEON', 50, ['THUNDERBOLT', 'SHADOWBALL'], item='CHOICESPECS',
         effects={'choiceband': 'THUNDERBOLT'}),
     mon('GARCHOMP', 50, ['EARTHQUAKE']),
     [('must_switch',)],
     [mon('SKARMORY', 50, ['BRAVEBIRD', 'ROOST'])]),

    # Every move at 0 PP: the only alternatives are Struggle or the bench.
    # Reborn forcedscore +200.
    ('switch_out_no_pp', 0,
     mon('SNORLAX', 50, ['BODYSLAM'], pp_all=0),
     mon('SUICUNE', 50, ['SURF']),
     [('must_switch',)],
     [mon('FERROTHORN', 50, ['POWERWHIP', 'GYROBALL'])]),

    # Drafted as doc scenarios (the +95/+125 triggers looked sub-gate), but the
    # reference showed Body Slam into bulky Suicune scores only 29, so both
    # cleared cleanly (yawn sss 45, chip 75, pivot 208.6) — upgraded to
    # must_switch on the recorded actions. The sss ladder across this shared
    # position — perish 170 > chip 75 > yawn 45 — is the measured trigger
    # ranking the doc versions were after anyway.
    ('switch_out_yawned', 0,
     mon('SNORLAX', 50, ['BODYSLAM'], effects={'yawn': 2}),
     mon('SUICUNE', 50, ['SURF']),
     [('must_switch',)],
     [mon('FERROTHORN', 50, ['POWERWHIP', 'GYROBALL'])]),

    ('switch_out_chip_stacked', 0,
     mon('SNORLAX', 50, ['BODYSLAM'], status='poison',
         effects={'leechseed': 0, 'toxic': 4}),
     mon('SUICUNE', 50, ['SURF']),
     [('must_switch',)],
     [mon('FERROTHORN', 50, ['POWERWHIP', 'GYROBALL'])]),
]

# ---------------------------------------------------------------------------
#  CORPUS_D1 — doubles, phase 1 (SIM-SPEC §9.12).
#
#  Deliberately NOT coordination scenarios. These are properties already proven
#  in singles, lifted onto a 2v2 field, so that a failure here means the HARNESS
#  built the position wrong rather than the AI reasoning wrong. They exercise,
#  in order: four battlers constructed and sent out; per-target scoring
#  (scorearray[target][move] on Reborn, one get_move_score call per (move,target)
#  on PBAI); target registration; apply_state on all four slots; and both AI
#  battlers being probed independently.
#
#  A doubles scenario carries its two extra actives in the trailing extra dict as
#  'format': 'double' plus 'ai2'/'player2'. Battler indices are 0 = player left,
#  1 = AI left, 2 = player right, 3 = AI right; 'left'/'right' in a must_target
#  assertion mean foe 0 and foe 2. Assertions carry {'actor': 1} to address the
#  AI's RIGHT battler; with no actor dict they address the left one, exactly as
#  in singles.
CORPUS_D1 = [
    # Per-target scoring, the single most important new mechanism. Electric is
    # worthless into Swampert (Water/Ground, immune) and 4x into Gyarados
    # (Water/Flying) — so a Thunderbolt aimed left is a wasted turn and one aimed
    # right is the best move on the field. An engine that scored moves without
    # reference to a target could not tell these apart. Flash Cannon is the
    # viable alternative (0.5x into both) so the vector is not degenerate.
    ('d_target_the_vulnerable_foe', 0,
     mon('MAGNEZONE', 50, ['THUNDERBOLT', 'FLASHCANNON']),
     mon('SWAMPERT', 50, ['WATERFALL', 'EARTHQUAKE']),
     [('must_choose_move_in', ['THUNDERBOLT']),
      ('must_target', 'right'),
      ('score_gt', 'THUNDERBOLT', 'FLASHCANNON')],
     {'format': 'double',
      'ai2': mon('SNORLAX', 50, ['BODYSLAM']),
      'player2': mon('GYARADOS', 50, ['WATERFALL'])}),

    # Spread damage with no upside. Both foes are Flying and take nothing from
    # Earthquake; the AI's own partner is grounded Steel and takes 2x. So EQ is
    # pure self-harm while Rock Slide is 2x into both foes. This is the property
    # a singles-only AI cannot express, and it is a genuine competence question
    # rather than a plumbing one — but it is safe to assert either way: even an
    # AI that never models ally damage still scores EQ at 0 into two immune
    # targets, so the move must lose on the foe side alone.
    ('d_spread_into_immune_foes', 0,
     mon('GOLEM', 50, ['EARTHQUAKE', 'ROCKSLIDE']),
     mon('GYARADOS', 50, ['WATERFALL']),
     [('must_not_choose_move', 'EARTHQUAKE'),
      ('score_gt', 'ROCKSLIDE', 'EARTHQUAKE')],
     {'format': 'double',
      'ai2': mon('MAGNEZONE', 50, ['THUNDERBOLT']),
      'player2': mon('CROBAT', 50, ['CROSSPOISON'])}),

    # State application on all four slots. Spore cannot land on a sleeping
    # target, and BOTH foes are asleep — if only one were, aiming Spore at the
    # other would be legitimate and the assertion would be wrong. A probe that
    # silently failed to apply status to battler 2 would leave the right foe
    # healthy and this would flip.
    ('d_status_not_reapplied_both_asleep', 0,
     mon('BRELOOM', 50, ['SPORE', 'SEEDBOMB']),
     mon('SNORLAX', 50, ['BODYSLAM'], status='sleep'),
     [('must_not_choose_move', 'SPORE')],
     {'format': 'double',
      'ai2': mon('MAGNEZONE', 50, ['THUNDERBOLT']),
      'player2': mon('GYARADOS', 50, ['WATERFALL'], status='sleep')}),

    # The right-hand AI battler is really probed, and its record is its own.
    # Every assertion here addresses actor 1; actor 0 is a bystander with a
    # single filler-padded move. Heatran's Fire STAB is 4x into Scizor
    # (Bug/Steel) while Flash Cannon is resisted, so actor 1 has an unambiguous
    # best move — and it is a DIFFERENT move slot from anything actor 0 would
    # pick, so a record that accidentally mirrored actor 0 would fail.
    ('d_right_actor_scored', 0,
     mon('SNORLAX', 50, ['BODYSLAM']),
     mon('GYARADOS', 50, ['WATERFALL']),
     [('must_choose_move_in', ['FLAMETHROWER'], {'actor': 1}),
      ('score_gt', 'FLAMETHROWER', 'FLASHCANNON', {'actor': 1}),
      ('must_target', 'right', {'actor': 1})],
     {'format': 'double',
      'ai2': mon('HEATRAN', 50, ['FLAMETHROWER', 'FLASHCANNON']),
      'player2': mon('SCIZOR', 50, ['BULLETPUNCH'])}),

    # Both AI battlers decide independently in the same position, each with a
    # different correct answer against a different foe. Left faces the Water
    # type and must go Electric; right faces the Bug/Steel and must go Fire.
    # Swapping either actor's record for the other's would fail both halves.
    ('d_both_actors_choose_moves', 0,
     mon('MAGNEZONE', 50, ['THUNDERBOLT', 'FLASHCANNON']),
     mon('GYARADOS', 50, ['WATERFALL']),
     [('must_choose_move_in', ['THUNDERBOLT']),
      ('must_choose_move_in', ['FLAMETHROWER'], {'actor': 1})],
     {'format': 'double',
      'ai2': mon('HEATRAN', 50, ['FLAMETHROWER', 'EARTHPOWER']),
      'player2': mon('SCIZOR', 50, ['BULLETPUNCH'])}),

    # A lethal move must beat a setup move, on a 2v2 field. Proven in singles;
    # repeated here because Reborn's doubles path reaches chooseAction through
    # coordinateActions, which rewrites scores before the choice is made — a
    # rewrite that loses track of a kill would show up here first.
    ('d_lethal_over_setup', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'SWORDSDANCE']),
     mon('MAGNEZONE', 50, ['THUNDERBOLT'], hp_pct=12),
     [('must_choose_move_in', ['EARTHQUAKE']),
      ('score_gt', 'EARTHQUAKE', 'SWORDSDANCE')],
     {'format': 'double',
      'ai2': mon('SNORLAX', 50, ['BODYSLAM']),
      'player2': mon('HEATRAN', 50, ['FLAMETHROWER'], hp_pct=12)}),
]

# ---------------------------------------------------------------------------
#  CORPUS_D2 — doubles, phase 2: the coordination layer (SIM-SPEC §9.13).
#
#  Reborn runs coordinateActions (PokeBattle_AI_2.rb:2092, 584 lines, doubles-only)
#  between scoring and choosing. It is the largest single block of the reference AI
#  that nothing in the corpus reached, and the only place the engine reads TURN
#  ORDER to decide who attacks whom. These four positions aim at its three
#  distinguishable behaviours: the spread-kills-both bonus (:2118, score *= 1.5),
#  the "don't both hit the same mon" assignment (:2145 and :2231 onward), and
#  target choice when one foe is finishable and the other is not.
#
#  Each assertion states play that is correct regardless of engine — overkill
#  wastes a turn, two kills beat one, and a teammate is not ammunition.
CORPUS_D2 = [
    # Two lethal options, one of which is lethal TWICE. Earthquake kills both
    # foes (Magnezone 2x, Heatran 4x, both left on a sliver); Stone Edge kills
    # one. The AI's own partner is Steel/FLYING and takes nothing from the
    # spread, so there is no downside to weigh — this isolates "does it notice a
    # move that resolves the whole field" from "does it model ally damage",
    # which is the next scenario's job.
    ('d_spread_kills_both_preferred', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'STONEEDGE']),
     mon('MAGNEZONE', 50, ['THUNDERBOLT'], hp_pct=15),
     [('must_choose_move_in', ['EARTHQUAKE']),
      ('score_gt', 'EARTHQUAKE', 'STONEEDGE')],
     {'format': 'double',
      'ai2': mon('SKARMORY', 50, ['BRAVEBIRD']),
      'player2': mon('HEATRAN', 50, ['FLAMETHROWER'], hp_pct=15)}),

    # The same spread move, now with the partner standing in it. Both foes are
    # Poison/Ground: Earthquake is 2x into each and Rock Slide is resisted, so
    # Earthquake is unambiguously the better move FOR THE FOE SIDE and an AI that
    # scores only against opponents must pick it. The cost is the AI's own
    # Magnezone at 25%, which 2x Ground removes outright. Spending a live
    # teammate to chip two healthy foes is a losing trade, so the property holds
    # for any competent player — but it can only be satisfied by an AI that
    # prices its own side, which is exactly what is being measured.
    ('d_spread_kills_own_partner', 0,
     mon('GOLEM', 50, ['EARTHQUAKE', 'ROCKSLIDE']),
     mon('NIDOKING', 50, ['EARTHQUAKE']),
     [('must_not_choose_move', 'EARTHQUAKE')],
     {'format': 'double',
      'ai2': mon('MAGNEZONE', 50, ['THUNDERBOLT'], hp_pct=25),
      'player2': mon('NIDOQUEEN', 50, ['EARTHQUAKE'])}),

    # Overkill, in a speed order the coordination layer actually acts on. Both AI
    # battlers can KO either foe, so the only question is who takes which — and
    # pointing both at the same one throws a turn away.
    #
    # The speed order is load-bearing and was chosen deliberately: Starmie 115 >
    # Zapdos 100 > Gyarados 81 > Snorlax 30 gives [2,1,0,3] (player, ai, player,
    # ai), which is the branch at PokeBattle_AI_2.rb:2291 that penalises each AI
    # mon against the foe standing next to it in the order and thereby splits
    # them. Both foes are left low enough that both AI mons genuinely threaten a
    # KO on both, which is the [:_,:both,:_,:both] precondition that branch
    # requires. Single-target moves on both sides, so the registered targets are
    # real choices rather than spread-move bookkeeping.
    ('d_split_targets_not_overkill', 0,
     mon('ZAPDOS', 50, ['THUNDERBOLT']),
     mon('GYARADOS', 50, ['WATERFALL'], hp_pct=20),
     [('must_not_double_target',)],
     {'format': 'double',
      'ai2': mon('SNORLAX', 50, ['BODYSLAM']),
      'player2': mon('STARMIE', 50, ['SURF'], hp_pct=30)}),

    # The same overkill question in the speed order Reborn REFUSES to answer.
    # Two identical Zapdos have identical score vectors, so nothing but
    # coordination can separate them; Starmie (115) outruns both and Gyarados
    # (81) trails both, giving [2,1,3,0] — player, ai, ai, player. That case is
    # handled at PokeBattle_AI_2.rb:2285, and its entire body is a comment:
    # "don't edit the scores, who knows which mon will live". It sets
    # targetting_done and returns, so both mons keep their identical vectors.
    #
    # MEASURED: both Zapdos fire Thunderbolt at the 20% Gyarados (121 each,
    # against 98 for the 55% Starmie) — one certain kill and one wasted turn.
    # Left as must_choose_any rather than must_not_double_target: the abstention
    # is deliberate and its stated reasoning (a foe acts between our two mons, so
    # the board may not be what we predicted) is defensible in general, even
    # though it costs a turn here. The enforceable version of the property is the
    # scenario above; this one records where the layer declines to apply it.
    ('d_double_target_abstention_documented', 0,
     mon('ZAPDOS', 50, ['THUNDERBOLT']),
     mon('GYARADOS', 50, ['WATERFALL'], hp_pct=20),
     [('must_choose_any',)],
     {'format': 'double',
      'ai2': mon('ZAPDOS', 50, ['THUNDERBOLT']),
      'player2': mon('STARMIE', 50, ['SURF'], hp_pct=55)}),

    # Target choice driven by HP alone. Both foes are the same species, so type
    # effectiveness, ability and bulk are identical and the only thing separating
    # them is that one is finishable this turn and the other is not. Finishing
    # removes a full attacker from the field; chipping the healthy one removes
    # nothing.
    #
    # Only the TARGET is asserted. Which move finishes the weakened foe is not a
    # competence question, and asserting it would be decided by a one-point margin
    # (measured on the reference at 8% HP: Thunderbolt 122, Flash Cannon 121).
    #
    # The weakened foe sits at 25%, not single digits, for a reason: at 8% every
    # move in the set — including the Pound/Peck fillers — was lethal, so PBAI's
    # whole vector tied and the checker correctly flagged the position degenerate,
    # meaning its target was picked at random and the assertion passed by luck. At
    # 25% only the 4x STAB is lethal, so the ranking is real on both engines.
    ('d_finish_the_finishable_foe', 0,
     mon('MAGNEZONE', 50, ['THUNDERBOLT', 'FLASHCANNON']),
     mon('GYARADOS', 50, ['WATERFALL']),
     [('must_target', 'right')],
     {'format': 'double',
      'ai2': mon('SNORLAX', 50, ['BODYSLAM']),
      'player2': mon('GYARADOS', 50, ['WATERFALL'], hp_pct=25)}),
]

# ---------------------------------------------------------------------------
#  CORPUS_V8 — move policy: is the move worth the turn it costs?
#
#  Written for Portable 0.4.0 (PORTABLE-AI-DIAGNOSIS.md). Every card here states a
#  property of competent play that the corpus did not previously constrain at all:
#  recovery that does not change who is alive, and a knockout picked without regard to
#  hit chance, speed, or what it costs the user. Reborn-Normal passes all of them on
#  stock behaviour; Portable 0.3.2 fails several, which is why they exist.
# ---------------------------------------------------------------------------
CORPUS_V8 = [
    # --- recovery that changes nothing --------------------------------------
    # Slower, and the incoming hit already kills: the heal never resolves. Gengar
    # rather than a Blissey-class healer so the hit is unambiguously lethal —
    # Psychic is 2x into a 60/60 defensive line, and Gengar (110) is slower than
    # Alakazam (120). Reborn's recovercode returns 0 here for a different reason
    # (the hit also exceeds the heal), so both engines agree on the answer.
    ('heal_slower_into_lethal_is_wasted', 0,
     mon('GENGAR', 50, ['RECOVER', 'SHADOWBALL'], hp_pct=12),
     mon('ALAKAZAM', 50, ['PSYCHIC']),
     [('score_gt', 'SHADOWBALL', 'RECOVER'),
      ('must_not_choose_move', 'RECOVER')]),

    # Faster, so the heal does resolve — and the hit kills through it anyway.
    # Crunch is 2x into Alakazam's 45 Def, far past 20% + a half heal.
    ('heal_that_still_dies_is_wasted', 0,
     mon('ALAKAZAM', 50, ['RECOVER', 'FOCUSBLAST'], hp_pct=20),
     mon('TYRANITAR', 50, ['CRUNCH']),
     [('score_gt', 'FOCUSBLAST', 'RECOVER'),
      ('must_not_choose_move', 'RECOVER')]),

    # The counter-case, and the reason the rule is a gate and not a ban: faster,
    # the hit would kill, and the heal is exactly what survives it. A rule that
    # only ever discourages recovery would pass the two cards above and fail here.
    # 25%: Snorlax's Body Slam measures 26.7% into this Starmie, so the hit kills from
    # here and a half heal outruns it. At 30% (the first draft) the hit was smaller than
    # the HP and the card passed on the plain low-HP bonus without ever reaching the
    # rule it is named for.
    ('heal_that_saves_when_faster', 0,
     mon('STARMIE', 50, ['RECOVER', 'SURF'], hp_pct=25),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('score_gt', 'RECOVER', 'SURF')]),

    # --- which knockout ------------------------------------------------------
    # Both are lethal and both are 4x into Volcarona, so nothing separates them but
    # hit chance: Rock Slide 90, Stone Edge 80. Reborn caps both at the same damage
    # score and then multiplies by (accuracy + 100) / 200, which is the whole
    # decision.
    ('accurate_ko_over_inaccurate_ko', 0,
     mon('AERODACTYL', 50, ['STONEEDGE', 'ROCKSLIDE']),
     mon('VOLCARONA', 50, ['FIREBLAST'], hp_pct=20),
     [('score_gt', 'ROCKSLIDE', 'STONEEDGE')]),

    # Slower than the foe (+2 Speed puts Garchomp past Weavile's 125) and the foe's
    # Earthquake kills first: the only knockout that happens is the priority one.
    # The existing priority_secures_kill_when_slower passes for the wrong reason —
    # Play Rough is resisted by Gengar's Poison typing, so `resisted` decides it —
    # so this card, not that one, is what tests the property.
    ('priority_ko_when_slower_real', 0,
     mon('WEAVILE', 50, ['ICESHARD', 'ICICLECRASH'], hp_pct=30),
     mon('GARCHOMP', 50, ['EARTHQUAKE'], hp_pct=15, stages={'spe': 2}),
     [('score_gt', 'ICESHARD', 'ICICLECRASH')]),

    # --- what the knockout costs ---------------------------------------------
    # Both kill Alakazam at 20%. One of them halves Hydreigon's Special Attack for
    # the rest of the fight. Portable clicked Draco Meteor 12.0 times per 1,000
    # turns against Reborn-Normal's 5.3.
    ('no_self_drop_when_alternative_kills', 0,
     mon('HYDREIGON', 50, ['DRACOMETEOR', 'DARKPULSE']),
     mon('ALAKAZAM', 50, ['PSYCHIC'], hp_pct=20),
     [('score_gt', 'DARKPULSE', 'DRACOMETEOR')]),

    # Both kill Starmie at 30%; one of them also ends Electrode. At full HP that is
    # never the trade. Portable exploded at 100% HP 15 times out of 21.
    ('no_explosion_at_full_hp_with_alternative', 0,
     mon('ELECTRODE', 50, ['EXPLOSION', 'THUNDERBOLT'], hp_pct=100),
     mon('STARMIE', 50, ['SURF'], hp_pct=30),
     [('score_gt', 'THUNDERBOLT', 'EXPLOSION'),
      ('must_not_choose_move', 'EXPLOSION')]),
]

# ---------------------------------------------------------------------------
#  CORPUS_V9 — move SIDE EFFECTS (Portable 0.5.0 Phase A, 2026-09-05).
#
#  0.5.0 ships Reborn's per-move valuations as data tables rather than as more
#  per-turn rules. Phase A writes one card per intended table row and runs STOCK
#  Reborn once, so each row is kept only where the reference agrees — the
#  heal_at_low_hp lesson (PORTABLE-AI-DIAGNOSIS.md): a rule copied from a reading
#  of the source, without a measurement, encoded a term Reborn does not have.
#
#  Each card names the branch it is about. Reborn multiplies a damage-percent score
#  by a `miniscore`, so the cards are built so the damage score stays well under the
#  100 cap — several branches (oppstatdrop:6243) switch themselves off at 100, and a
#  capped pair ties, which the checker correctly calls degenerate.
# ---------------------------------------------------------------------------
CORPUS_V9 = [
    # --- recoil (recoilcode:8148) -------------------------------------------
    # The whole recoil term is a flat 0.9 (plus 0.7 when the USER would survive the
    # foe's best hit, and 0.8 in a 10-40% HP band). It is not scaled by the recoil
    # fraction and it is not waived on a kill. So a 120 BP recoil move must still
    # beat an 80 BP clean one: the card exists to fix how small the penalty is.
    # Snorlax is neutral to Flying and bulky enough that neither move caps.
    ('recoil_flat_penalty_vs_equal_power', 0,
     mon('STARAPTOR', 50, ['BRAVEBIRD', 'DRILLPECK']),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('score_gt', 'BRAVEBIRD', 'DRILLPECK')]),

    # The same pair with the user at 8% HP and a foe that BOTH moves kill. Brave
    # Bird's 33% recoil is far more than 8% of Staraptor, so clicking it wins the
    # battler and loses the Pokemon while Drill Peck wins both. recoilcode has no
    # "the recoil kills me" term outside a sleep/frozen branch (:8153), but the flat
    # 0.9 is enough here on its own -- MEASURED: Brave Bird 74 against Drill Peck 82.
    # Every lethal move ties at the kill score, the padded PECK filler included (82),
    # so the property is stated as a ban on the recoil move rather than as a choice
    # of one particular move.
    ('recoil_move_that_kills_self_still_clicked', 0,
     mon('STARAPTOR', 50, ['BRAVEBIRD', 'DRILLPECK'], hp_pct=8),
     mon('BRELOOM', 50, ['SEEDBOMB'], hp_pct=60),
     [('must_not_choose_move', 'BRAVEBIRD'),
      ('score_gt', 'DRILLPECK', 'BRAVEBIRD')]),

    # The 10% < hp < 40% band (:8153, x0.8). Same pair, nothing lethal, user at 30%:
    # measures whether the extra 0.8 is enough to flip a 120/80 BP gap. It should
    # not be (120 x 0.72 > 80), which is itself the finding.
    ('recoil_cheaper_when_low_hp', 0,
     mon('STARAPTOR', 50, ['BRAVEBIRD', 'DRILLPECK'], hp_pct=30),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('score_gt', 'BRAVEBIRD', 'DRILLPECK')]),

    # --- drain (absorbcode:7741) --------------------------------------------
    # Damaged, so the drain is worth real HP. absorbcode's whole term is
    # min(score,100) x opp.hp / 200 divided by the OPPONENT's max HP (:7749) — the
    # user's own missing HP never enters it — so it is bounded by x1.25 and reaches
    # that bound only when the move already scores 100. Quagsire is Water/Ground and
    # takes 4x from both Grass moves, which is what puts them there; on a neutral
    # target the term is worth about x1.09 and 75 BP stays behind 90 BP (MEASURED:
    # Giga Drain 35 against Energy Ball 42 into a healthy Starmie).
    ('drain_valued_when_damaged', 0,
     mon('LUDICOLO', 50, ['GIGADRAIN', 'ENERGYBALL'], hp_pct=40),
     mon('QUAGSIRE', 50, ['EARTHQUAKE'], ability='DAMP'),
     [('score_gt', 'GIGADRAIN', 'ENERGYBALL')]),

    # The guard clause: at full HP and faster, absorbcode returns 1 flat (:7742) —
    # there is no HP to restore and the drain resolves after the hit anyway. The
    # 90 BP move must win. Snorlax is slower than Ludicolo and neutral to Grass.
    ('drain_worthless_at_full_hp_when_faster', 0,
     mon('LUDICOLO', 50, ['GIGADRAIN', 'ENERGYBALL']),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('score_gt', 'ENERGYBALL', 'GIGADRAIN')]),

    # --- flinch (flinchcode:5689) -------------------------------------------
    # Faster, and the move does not kill: the flinch chance is live and worth x1.3
    # (:5694, only while the user has no already-great move). Rock Slide 75 keeps
    # its BP lead over Rock Tomb 60. Milotic is neutral to Rock and slower than
    # Aerodactyl (81 vs 130).
    ('flinch_valued_when_faster', 0,
     mon('AERODACTYL', 50, ['ROCKSLIDE', 'ROCKTOMB']),
     mon('MILOTIC', 50, ['SURF']),
     [('score_gt', 'ROCKSLIDE', 'ROCKTOMB')]),

    # The same position with the foe at +2 Speed (81 -> 162, past Aerodactyl's 130).
    # flinchcode returns a flat 1 when slower (:5691) — a flinch you never inflict
    # is worth nothing — while Rock Tomb's Speed drop becomes live, and its x1.5
    # (:6296) fires because 0.66 x 162 is still under 130. Whether that is enough to
    # overturn 15 BP is the measurement.
    ('flinch_ignored_when_slower', 0,
     mon('AERODACTYL', 50, ['ROCKSLIDE', 'ROCKTOMB']),
     mon('MILOTIC', 50, ['SURF'], stages={'spe': 2}),
     [('score_gt', 'ROCKTOMB', 'ROCKSLIDE')]),

    # --- secondary status (burncode:5637, paracode:5597) --------------------
    # Scald 80 vs Surf 90 into a physical attacker: burncode is 1.2, x1.4 again
    # because Machamp's Attack beats its Special Attack (:5662), so the weaker move
    # should win by a distance. NOTE the term Reborn does NOT have: burncode never
    # reads the move's addlEffect, so Scald's 30% and Will-O-Wisp's 100% are priced
    # the same. That is the row 0.5.0 must decide whether to copy or correct.
    ('secondary_burn_vs_physical_attacker', 0,
     mon('MILOTIC', 50, ['SCALD', 'SURF']),
     mon('MACHAMP', 50, ['CLOSECOMBAT'], ability='NOGUARD'),
     [('score_gt', 'SCALD', 'SURF')]),

    # The control for the x1.4: same pair into a special attacker, where the burn
    # does far less and the 10 BP gap should decide instead. A rule that valued burn
    # unconditionally would pass the card above and fail this one.
    ('secondary_burn_vs_special_attacker', 0,
     mon('MILOTIC', 50, ['SCALD', 'SURF']),
     mon('ALAKAZAM', 50, ['PSYCHIC']),
     [('score_gt', 'SURF', 'SCALD')]),

    # Paralysis, priced by whether it flips the speed order. paracode multiplies by
    # 1.2 when the user is slower and the foe's HALVED Speed would fall behind it
    # (:5615), and by another 1.2 against a full-HP target. Snorlax (30) is slower
    # than Machamp (55) and 55/2 = 27.5 is under 30, so both terms are live.
    # Body Slam 85 (function 0x07, paralysis) against Strength 80 (no secondary at
    # all) isolates the term: the FIRST draft paired Discharge with Thunderbolt, and
    # both are function 0x07 in this engine, so paracode applied to both and
    # cancelled out (MEASURED: Discharge 38, Thunderbolt 41 — the raw BP ratio).
    ('secondary_para_valued_when_it_flips_the_order', 0,
     mon('SNORLAX', 50, ['BODYSLAM', 'STRENGTH'], ability='THICKFAT'),
     mon('MACHAMP', 50, ['CLOSECOMBAT'], ability='NOGUARD'),
     [('score_gt', 'BODYSLAM', 'STRENGTH')]),

    # Immunity comes from the engine's own can-status check, not a type list:
    # burncode's first line is `!@opponent.pbCanBurn?` (:5638), and a Fire type
    # cannot burn. With the secondary worth nothing, the 90 BP move must win — the
    # exact reversal of secondary_burn_vs_physical_attacker.
    ('secondary_burn_dropped_vs_fire_type', 0,
     mon('MILOTIC', 50, ['SCALD', 'SURF']),
     mon('ARCANINE', 50, ['FLAREBLITZ'], ability='INTIMIDATE'),
     [('score_gt', 'SURF', 'SCALD')]),

    # Sheer Force removes the secondary outright (secondaryEffectNegated?:17430), so
    # Sludge Bomb's poison chance is worth nothing to Nidoking and the two moves are
    # separated by type and power alone. Earth Power is 2x into Nidoqueen
    # (Poison/Ground) where Sludge Bomb is 0.5x, so with the secondary gone the
    # ranking is unambiguous.
    ('secondary_dropped_by_sheer_force', 0,
     mon('NIDOKING', 50, ['SLUDGEBOMB', 'EARTHPOWER'], ability='SHEERFORCE'),
     mon('NIDOQUEEN', 50, ['EARTHQUAKE']),
     [('score_gt', 'EARTHPOWER', 'SLUDGEBOMB')]),

    # --- target stat drops on damaging moves (oppstatdrop:6242) -------------
    # A Speed drop is deleted outright when the user is already faster (:6270) and
    # worth x1.5 when it can bring the foe into range (:6296, needs 0.66 x foe speed
    # under our own). Aerodactyl at -2 Speed (130 -> 65) is slower than Milotic's 81
    # and 0.66 x 81 = 53 is under 65, so both conditions hold. Icy Wind 55 against
    # Ice Beam 90 is a 35 BP deficit for the drop to overcome — deliberately more
    # than the term can plausibly pay, so a pass would be a surprise worth having.
    #
    # MEASURED (stock, 2026-09-05): Icy Wind 5, Ice Beam 4 -- a one-point margin on a
    # position where both padded fillers outscore both real moves (Peck 15 takes the
    # choice). Aerodactyl's 60 Special Attack is why: neither Ice move does enough for
    # a x1.3 on it to mean anything. Left as a documenting card rather than a
    # guardrail; d_icy_wind_speed_control in CORPUS_D3 is the version of this row with
    # a real margin behind it, and is what the 0.5.0 speed-drop rule is calibrated on.
    ('stat_drop_speed_when_slower', 0,
     mon('AERODACTYL', 50, ['ICYWIND', 'ICEBEAM'], stages={'spe': -2}),
     mon('MILOTIC', 50, ['SURF']),
     [('must_choose_any',)]),

    # A Special Attack drop into a special attacker. oppstatdrop keeps the SpA row
    # only when the foe is not a physical attacker (:6266) — Alakazam is 50/135, so
    # it survives — and Moonblast 95 already out-powers Dazzling Gleam 80, so this
    # card checks that the drop is at least not thrown away. Fairy is neutral into
    # Psychic, so nothing caps.
    ('stat_drop_spa_vs_special_attacker', 0,
     # Super Luck rather than the slot-0 Hustle, whose accuracy penalty on the
     # padded physical fillers would move the ranking for an unrelated reason,
     # and rather than Serene Grace, which doubles the drop chance the card is
     # trying to price (pbSereneGraceCheck:9875).
     mon('TOGEKISS', 50, ['MOONBLAST', 'DAZZLINGGLEAM'], ability='SUPERLUCK'),
     mon('ALAKAZAM', 50, ['PSYCHIC']),
     [('score_gt', 'MOONBLAST', 'DAZZLINGGLEAM')]),

    # --- item removal (knockcode:8072) --------------------------------------
    # Knock Off 65 against Night Slash 70: the item is the only thing that can carry
    # it. knockcode is a short whitelist — Leftovers and Black Sludge 1.3, Life Orb
    # / the Choice items / Assault Vest 1.2, everything else 1.0 — so a Leftovers
    # holder is the one case where 5 BP is affordable.
    ('knockoff_vs_leftovers', 0,
     mon('WEAVILE', 50, ['KNOCKOFF', 'NIGHTSLASH']),
     mon('SNORLAX', 50, ['BODYSLAM'], item='LEFTOVERS'),
     [('score_gt', 'KNOCKOFF', 'NIGHTSLASH')]),

    # No item, so knockcode returns 1 on its guard clause (:8073) and the 70 BP move
    # must win. Same position otherwise.
    ('knockoff_vs_no_item', 0,
     mon('WEAVILE', 50, ['KNOCKOFF', 'NIGHTSLASH']),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('score_gt', 'NIGHTSLASH', 'KNOCKOFF')]),

    # Focus Sash is not on knockcode's whitelist, but Knock Off still wins — because
    # the ENGINE's damage calc already multiplies it against any item holder, and
    # that reaches the AI through pbRoughDamage without knockcode's help. The three
    # cards MEASURE as Knock Off 75 (Leftovers) / 58 (Sash) / 39 (no item) against a
    # flat Night Slash 42: the 58 is the damage boost alone and the 75 is the boost
    # plus the whitelist's x1.3. So the 0.5.0 row is the whitelist ONLY — the rest is
    # already in the numbers the adapter exports.
    ('knockoff_vs_focus_sash_boosted_but_not_whitelisted', 0,
     mon('WEAVILE', 50, ['KNOCKOFF', 'NIGHTSLASH']),
     mon('SNORLAX', 50, ['BODYSLAM'], item='FOCUSSASH'),
     [('score_gt', 'KNOCKOFF', 'NIGHTSLASH')]),

    # --- multi-hit (multihitcode:7385) --------------------------------------
    # Icicle Spear 25x5 against a full-HP Focus Sash holder: multihitcode adds x1.3
    # when notOHKO? says the target survives one hit (:7389), which is exactly what
    # a Sash does — and a multi-hit move is the answer to it. Icicle Crash 85 is the
    # single-hit alternative: same type AND same category, so the target's defences
    # cancel and only the Sash separates them. Pairing it with the special Ice Beam
    # instead measured the 120 Def / 60 SpD split of the target and nothing else.
    #
    # The target is pinned FASTER (+2 Speed) for a second reason found the same way:
    # Icicle Crash flinches, and against a slower target flinchcode paid it its own
    # x1.3, which cancelled the Sturdy/Sash bonus almost exactly (MEASURED at 59
    # against 60). flinchcode returns a flat 1 when the user is slower (:5691), so
    # with the order reversed the multi-hit term is the only one left standing.
    # Cloyster's slot-0 ability is Shell Armor, not Skill Link, so the hit count is
    # the engine's ordinary 2-5 roll.
    ('multihit_breaks_sash', 0,
     mon('CLOYSTER', 50, ['ICICLESPEAR', 'ICICLECRASH']),
     mon('MACHAMP', 50, ['CLOSECOMBAT'], ability='NOGUARD', item='FOCUSSASH',
         stages={'spe': 2}),
     [('score_gt', 'ICICLESPEAR', 'ICICLECRASH')]),
]

# ---------------------------------------------------------------------------
#  CORPUS_V10 — abilities, items and entry (Portable 0.5.0 Phase A, 2026-09-05).
#
#  Same protocol as V9: one card per intended 0.5.0 table row, graded against STOCK
#  Reborn before any rule is written. Several cards here deliberately bench TWO of
#  one species differing only in an ability or a held item — that is the only way to
#  price an ability without a typing or bulk difference paying for it — so they
#  address the candidates as bench0/bench1 rather than by name.
#
#  switch_score_gt cards need the active to genuinely want out: Reborn only fills
#  switchscore when shouldSwitch? already came out positive (:11358), so each of
#  them reuses a shape the corpus has already proven triggers it (a foe whose shown
#  move is an OHKO, CORPUS_V5 switch_out_vs_fresh_ohko_counter).
# ---------------------------------------------------------------------------
CORPUS_V10 = [
    # --- surviving one hit (notOHKO?:17401) ---------------------------------
    # Sturdy at full HP means the "kill" does not kill. multihitcode reads exactly
    # that through notOHKO? (:7389, x1.3), and a multi-hit move is the real answer.
    # Donphan is Ground, so both Ice moves are 2x, and both are PHYSICAL — its 120
    # Def / 60 SpD split would otherwise decide the card by itself (MEASURED with
    # the special Ice Beam as the comparator: Icicle Spear 59, Ice Beam 83). It is
    # also pinned FASTER so Icicle Crash collects no flinch bonus of its own; see
    # multihit_breaks_sash in CORPUS_V9 for the measurement that forced that.
    ('sturdy_blocks_the_kill_call', 0,
     mon('CLOYSTER', 50, ['ICICLESPEAR', 'ICICLECRASH']),
     mon('DONPHAN', 50, ['EARTHQUAKE'], ability='STURDY', stages={'spe': 2}),
     [('score_gt', 'ICICLESPEAR', 'ICICLECRASH')]),

    # Focus Sash is the same fact from an item (:17409). Same position, Sand Veil
    # pinned instead of Sturdy so the Sash is the only thing keeping it alive.
    ('focus_sash_same_as_sturdy', 0,
     mon('CLOYSTER', 50, ['ICICLESPEAR', 'ICICLECRASH']),
     mon('DONPHAN', 50, ['EARTHQUAKE'], ability='SANDVEIL', item='FOCUSSASH',
         stages={'spe': 2}),
     [('score_gt', 'ICICLESPEAR', 'ICICLECRASH')]),

    # notOHKO? bails at its third line when the target is not at full HP (:17404),
    # so a Sash holder at 90% is an ordinary target and the multi-hit bonus must be
    # gone. The reversal that stops the rule from being "multi-hit is just better".
    ('sash_ignored_when_not_full_hp', 0,
     mon('CLOYSTER', 50, ['ICICLESPEAR', 'ICICLECRASH']),
     mon('DONPHAN', 50, ['EARTHQUAKE'], ability='SANDVEIL', item='FOCUSSASH',
         hp_pct=90, stages={'spe': 2}),
     [('score_gt', 'ICICLECRASH', 'ICICLESPEAR')]),

    # Mold Breaker turns Sturdy off, and notOHKO? checks for it by name
    # (moldBreakerCheck at :17408), so the multi-hit bonus must disappear again —
    # this time because of the USER's ability rather than the target's HP.
    # Excadrill's Ground STAB is the pair's other half; Iron Head is Steel, which
    # Donphan takes neutrally, so only the Sturdy term separates them.
    ('mold_breaker_ignores_sturdy', 0,
     mon('EXCADRILL', 50, ['ROCKSLIDE', 'IRONHEAD'], ability='MOLDBREAKER'),
     mon('DONPHAN', 50, ['EARTHQUAKE'], ability='STURDY'),
     [('must_choose_any',)]),

    # --- Intimidate on the way in (:11584-11597) ----------------------------
    # Two Arcanine on the bench, identical in every stat and type, differing only in
    # Intimidate vs Flash Fire. Reborn's switch-in estimate applies a real -1 Attack
    # stage to each foe before it measures the incoming damage (:11586), so the
    # Intimidate holder must come out ahead against a physical attacker. Mamoswine's
    # Icicle Crash is 4x into Garchomp AND physical: it is both the OHKO that makes
    # the active want out and the hit Intimidate is meant to soften, in the shape
    # CORPUS_V5's switch_out_vs_fresh_ohko_counter proved fills switchscore.
    # A first draft used a 30% Alakazam against Metagross; shouldSwitch? never went
    # positive there, switch_scores came back EMPTY (:11358 gates it), and nothing
    # was measurable — which is why every switch_score_gt card reuses this shape.
    ('intimidate_switchin_lowers_incoming', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'DRAGONCLAW'], ability='SANDVEIL'),
     mon('MAMOSWINE', 50, ['ICICLECRASH'], ability='OBLIVIOUS'),
     [('switch_score_gt', 'bench0', 'bench1')],
     [mon('ARCANINE', 50, ['FLAREBLITZ', 'CRUNCH'], ability='INTIMIDATE'),
      mon('ARCANINE', 50, ['FLAREBLITZ', 'CRUNCH'], ability='FLASHFIRE')]),

    # The same board with the foe holding a Clear Amulet, which pbCanReduceStatStage?
    # refuses the drop for (PokeBattle_Effects.rb:704) — as it does for Clear Body,
    # White Smoke, Full Metal Body and Hyper Cutter. Reborn's own exemption list at
    # :11594 names only White Herb / Contrary / Mirror Armor / Defiant, but the
    # engine check underneath covers the rest, so the Intimidate edge should vanish
    # here and the two Arcanine should score the same. Open, because "equal" is what
    # is being measured: the pair's value is the delta between the two records.
    ('intimidate_ignored_vs_clear_amulet', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'DRAGONCLAW'], ability='SANDVEIL'),
     mon('MAMOSWINE', 50, ['ICICLECRASH'], ability='OBLIVIOUS',
         item='CLEARAMULET'),
     [('must_choose_any',)],
     [mon('ARCANINE', 50, ['FLAREBLITZ', 'CRUNCH'], ability='INTIMIDATE'),
      mon('ARCANINE', 50, ['FLAREBLITZ', 'CRUNCH'], ability='FLASHFIRE')]),

    # --- reflected and blocked status ---------------------------------------
    # Magic Bounce on the target returns -1 for every non-damaging move (:2828), so
    # both Stealth Rock and Toxic are unusable and the attack is the only real
    # option. Espeon is Psychic, so Earthquake is neutral and beats the padded
    # fillers on power alone.
    ('magic_bounce_blocks_hazards', 0,
     mon('GARCHOMP', 50, ['STEALTHROCK', 'TOXIC', 'EARTHQUAKE']),
     mon('ESPEON', 50, ['PSYCHIC'], ability='MAGICBOUNCE'),
     [('must_choose_move_in', ['EARTHQUAKE']),
      ('score_gt', 'EARTHQUAKE', 'TOXIC')]),

    # Prankster gives status moves priority, and a Dark type ignores it — Reborn
    # returns a flat 0 for the whole move (:3324) rather than discounting it. Foul
    # Play is the alternative and is 2x into Tyranitar's Dark/Rock, so the ranking
    # is not close.
    ('prankster_status_fails_vs_dark', 0,
     mon('SABLEYE', 50, ['WILLOWISP', 'FOULPLAY'], ability='PRANKSTER'),
     mon('TYRANITAR', 50, ['CRUNCH']),
     [('must_choose_move_in', ['FOULPLAY']),
      ('score_gt', 'FOULPLAY', 'WILLOWISP')]),

    # Misty Terrain (field 3) blocks status on a grounded target through
    # pbCanStatus? (PokeBattle_Effects.rb:696), which poisoncode reads. Seismic Toss
    # is a flat 50 damage, which against a target with Blissey's HP is a smaller
    # score than Toxic — so on an open field Toxic wins (the control below) and only
    # the terrain can move it. A first draft used Starmie, whose 140 HP made the
    # flat 50 worth MORE than Toxic (37 against 25) and broke the control.
    ('misty_terrain_blocks_status', 3,
     mon('BLISSEY', 50, ['TOXIC', 'SEISMICTOSS'], ability='HEALER'),
     mon('BLISSEY', 50, ['SEISMICTOSS'], ability='HEALER'),
     [('must_not_choose_move', 'TOXIC'),
      ('score_gt', 'SEISMICTOSS', 'TOXIC')]),

    # MEASURED: stock Reborn Toxic 30 / Seismic Toss 15, Portable 0.5.0 Toxic 125 /
    # Seismic Toss 182. The two disagree because pbRoughDamage returns a full-HP figure
    # for Seismic Toss -- a fixed-damage move Reborn's own scorer handles on a separate
    # path -- so the adapter hands the core a 100% hit where the reference sees 14%.
    # That is an adapter fidelity gap for fixed-damage moves, not a 0.5.0 row, and it
    # is why this control documents rather than asserts. The card it controls,
    # natural_cure_devalues_status, is a Reborn-side guardrail: Portable satisfies it
    # for the unrelated reason that it barely values a status move at all.
    ('toxic_valued_on_open_field', 0,
     mon('BLISSEY', 50, ['TOXIC', 'SEISMICTOSS'], ability='HEALER'),
     mon('BLISSEY', 50, ['SEISMICTOSS'], ability='HEALER'),
     [('must_choose_any',)]),

    # --- abilities that price a status or a boost ---------------------------
    # Natural Cure walks the status off on the switch, and poisoncode prices that at
    # x0.3 (the burncode:5647 row). The control is toxic_valued_on_open_field above:
    # the SAME Blissey on the SAME field, pinned to its hidden Healer instead, so the
    # only difference between the two records is the ability under test.
    ('natural_cure_devalues_status', 0,
     mon('BLISSEY', 50, ['TOXIC', 'SEISMICTOSS'], ability='HEALER'),
     mon('BLISSEY', 50, ['SEISMICTOSS'], ability='NATURALCURE'),
     [('score_gt', 'SEISMICTOSS', 'TOXIC')]),

    # Guts turns a burn into an Attack boost, and burncode prices it at x0.1
    # (:5650) — the largest deterrent in the table. Will-O-Wisp into Conkeldurr is
    # the textbook mistake; Seismic Toss is the alternative.
    ('guts_devalues_burn', 0,
     mon('BLISSEY', 50, ['WILLOWISP', 'SEISMICTOSS'], ability='HEALER'),
     mon('CONKELDURR', 50, ['CLOSECOMBAT'], ability='GUTS'),
     [('score_gt', 'SEISMICTOSS', 'WILLOWISP'),
      ('must_not_choose_move', 'WILLOWISP')]),

    # Unaware ignores the boosts, so setting up in front of it achieves nothing;
    # Reborn halves the setup score (:4966). Quagsire is Water/Ground, so Dragon
    # Claw is neutral and is the move that should win.
    ('unaware_devalues_setup', 0,
     mon('SALAMENCE', 50, ['DRAGONDANCE', 'DRAGONCLAW'], ability='MOXIE'),
     mon('QUAGSIRE', 50, ['EARTHQUAKE'], ability='UNAWARE'),
     [('score_gt', 'DRAGONCLAW', 'DRAGONDANCE'),
      ('must_not_choose_move', 'DRAGONDANCE')]),

    # Contrary turns Leaf Storm's -2 Special Attack into +2, which is the reason to
    # click it. Giga Drain is the same type at 75 BP with no drawback, so a scorer
    # that only ever charges for a self-drop would rank them the wrong way round.
    # Donphan is Ground: both Grass moves are 2x, neither caps.
    ('contrary_flips_leaf_storm', 0,
     mon('SERPERIOR', 50, ['LEAFSTORM', 'GIGADRAIN'], ability='CONTRARY'),
     mon('DONPHAN', 50, ['EARTHQUAKE'], ability='SANDVEIL'),
     [('score_gt', 'LEAFSTORM', 'GIGADRAIN')]),

    # --- hazards and Heavy-Duty Boots ---------------------------------------
    # Spikes are worth laying only against a party that can be hurt by them.
    # Reborn's 0x103 branch walks the whole opposing party and skips Boots holders
    # (:4603), then multiplies the score by 0 when the count reaches zero (:4627).
    # Every player mon here holds Boots, so Spikes must lose to the attack.
    # The party is SIX mons because hazardcode scales with bench size — x0.2 at two
    # benched, 0.25 x count above that (:8888) — and Magnezone resists Brave Bird,
    # because a first draft measured Spikes at 7 against a 2x Brave Bird at 73 and
    # the control could not have passed however well the Boots check worked.
    ('spikes_hit_nobody_with_boots', 0,
     mon('SKARMORY', 50, ['SPIKES', 'BRAVEBIRD'], ability='KEENEYE'),
     mon('MAGNEZONE', 50, ['THUNDERBOLT'], ability='ANALYTIC',
         item='HEAVYDUTYBOOTS'),
     [('must_not_choose_move', 'SPIKES'),
      ('score_gt', 'BRAVEBIRD', 'SPIKES')],
     {'player_bench': [mon('SNORLAX', 50, ['BODYSLAM'], item='HEAVYDUTYBOOTS'),
                       mon('ALAKAZAM', 50, ['PSYCHIC'], item='HEAVYDUTYBOOTS'),
                       mon('MACHAMP', 50, ['CLOSECOMBAT'], item='HEAVYDUTYBOOTS'),
                       mon('STARMIE', 50, ['SURF'], item='HEAVYDUTYBOOTS'),
                       mon('TYRANITAR', 50, ['CRUNCH'], item='HEAVYDUTYBOOTS')]}),

    # The control: the same party without the Boots, where Spikes are worth laying.
    # Without this card the one above would pass for an AI that never lays hazards.
    ('spikes_valued_without_boots', 0,
     mon('SKARMORY', 50, ['SPIKES', 'BRAVEBIRD'], ability='KEENEYE'),
     mon('MAGNEZONE', 50, ['THUNDERBOLT'], ability='ANALYTIC'),
     [('score_gt', 'SPIKES', 'BRAVEBIRD')],
     {'player_bench': [mon('SNORLAX', 50, ['BODYSLAM']),
                       mon('ALAKAZAM', 50, ['PSYCHIC']),
                       mon('MACHAMP', 50, ['CLOSECOMBAT']),
                       mon('STARMIE', 50, ['SURF']),
                       mon('TYRANITAR', 50, ['CRUNCH'])]}),

    # Stealth Rock's branch (0x105, :4670) has no such party walk at all — no Boots
    # check, no immunity count. Against the IDENTICAL all-Boots party where Spikes
    # collapse to 0, Stealth Rock keeps its full value.
    #
    # MEASURED: stock Reborn 45 against a 7 for the attack, Portable 0.5.0 -500 (its
    # hazard rule applies the Boots exclusion to every hazard, not just to Spikes).
    # Documented rather than asserted, and asserted in NEITHER direction: laying rocks
    # against a party that all holds Boots is not good play, so the reference's number
    # is a blind spot and not a property, and a card may only assert a property.
    ('stealth_rock_ignores_boots', 0,
     mon('SKARMORY', 50, ['STEALTHROCK', 'BRAVEBIRD'], ability='KEENEYE'),
     mon('MAGNEZONE', 50, ['THUNDERBOLT'], ability='ANALYTIC',
         item='HEAVYDUTYBOOTS'),
     [('must_choose_any',)],
     {'player_bench': [mon('SNORLAX', 50, ['BODYSLAM'], item='HEAVYDUTYBOOTS'),
                       mon('ALAKAZAM', 50, ['PSYCHIC'], item='HEAVYDUTYBOOTS'),
                       mon('MACHAMP', 50, ['CLOSECOMBAT'], item='HEAVYDUTYBOOTS'),
                       mon('STARMIE', 50, ['SURF'], item='HEAVYDUTYBOOTS'),
                       mon('TYRANITAR', 50, ['CRUNCH'], item='HEAVYDUTYBOOTS')]}),

    # Boots on the way IN, rather than on the way out. Two Charizard on the bench,
    # identical but for the item, with Stealth Rock on the AI's own side: one takes
    # 50% walking in and the other takes nothing, so the Boots holder must be the
    # better switch. totalHazardDamage (:10454) is the function that would price it.
    ('heavy_duty_boots_entry', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'DRAGONCLAW'], ability='SANDVEIL'),
     mon('MAMOSWINE', 50, ['ICICLECRASH'], ability='OBLIVIOUS'),
     [('switch_score_gt', 'bench0', 'bench1')],
     [mon('CHARIZARD', 50, ['FLAMETHROWER', 'AIRSLASH'], item='HEAVYDUTYBOOTS'),
      mon('CHARIZARD', 50, ['FLAMETHROWER', 'AIRSLASH'])],
     {'ai_side': {'stealthrock': 1}}),

    # Both switch_score_gt cards above compare two bench mons that differ in one
    # ability or one item, and both are decided by a difference of tens of points on
    # numbers the record does not explain. Reborn evaluates candidates in party order
    # and mutates the FOE's Attack stage while it does so (:11586, restored at
    # :11617), so "the first bench slot scores better" is a live alternative
    # explanation for both. These two cards are the same boards with the bench order
    # reversed: if the property is real it survives the swap, and if it is an
    # artifact of evaluation order the pair disagrees.
    ('intimidate_switchin_order_swapped', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'DRAGONCLAW'], ability='SANDVEIL'),
     mon('MAMOSWINE', 50, ['ICICLECRASH'], ability='OBLIVIOUS'),
     [('switch_score_gt', 'bench1', 'bench0')],
     [mon('ARCANINE', 50, ['FLAREBLITZ', 'CRUNCH'], ability='FLASHFIRE'),
      mon('ARCANINE', 50, ['FLAREBLITZ', 'CRUNCH'], ability='INTIMIDATE')]),

    ('heavy_duty_boots_entry_order_swapped', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'DRAGONCLAW'], ability='SANDVEIL'),
     mon('MAMOSWINE', 50, ['ICICLECRASH'], ability='OBLIVIOUS'),
     [('switch_score_gt', 'bench1', 'bench0')],
     [mon('CHARIZARD', 50, ['FLAMETHROWER', 'AIRSLASH']),
      mon('CHARIZARD', 50, ['FLAMETHROWER', 'AIRSLASH'], item='HEAVYDUTYBOOTS')],
     {'ai_side': {'stealthrock': 1}}),

    # --- a choice-locked foe is a one-move threat ---------------------------
    # Heatran is locked into Earth Power, which Skarmory is immune to; its other
    # move, Flamethrower, is 2x. If the lock is read, Roost at 20% is free and
    # obviously right.
    #
    # MEASURED (stock, 2026-09-05): Roost scores 0 and the AI clicks Brave Bird at
    # 11, which is 0.25x into Fire/Steel. recovercode zeroes the heal because it
    # still believes an incoming 2x Flamethrower kills through it — the move scorer
    # does NOT restrict the threat model to the locked move, even though
    # getSwitchInScoresParty does exactly that four thousand lines away (:11377,
    # PBEffects::ChoiceBand picked up as `incomingmove`). Documented rather than
    # asserted: the property is right and the reference does not have it, so it
    # belongs to 0.5.0's strict_threat row and to a unit test, not to the guardrail.
    ('choice_locked_foe_threat_is_one_move', 0,
     mon('SKARMORY', 50, ['ROOST', 'BRAVEBIRD'], ability='KEENEYE', hp_pct=20),
     mon('HEATRAN', 50, ['FLAMETHROWER', 'EARTHPOWER'], ability='FLASHFIRE',
         item='CHOICESCARF', effects={'choiceband': 'EARTHPOWER'}),
     [('must_choose_any',)]),

    # --- terrain that rewrites priority -------------------------------------
    # Psychic Terrain (field 37) stops priority moves from reaching a grounded
    # target, so Aqua Jet cannot secure the kill and Waterfall must be preferred.
    # Donphan at +2 Speed outruns Azumarill, so priority is the only way to move
    # first; at 25% HP with Huge Power both moves are lethal, which is what makes
    # the priority term the whole difference. Paired with the field-0 control below.
    ('psychic_terrain_blocks_priority', 37,
     mon('AZUMARILL', 50, ['AQUAJET', 'WATERFALL'], ability='HUGEPOWER'),
     mon('DONPHAN', 50, ['EARTHQUAKE'], ability='SANDVEIL', hp_pct=25,
         stages={'spe': 2}),
     [('score_gt', 'WATERFALL', 'AQUAJET')]),

    ('priority_ko_valued_on_open_field', 0,
     mon('AZUMARILL', 50, ['AQUAJET', 'WATERFALL'], ability='HUGEPOWER'),
     mon('DONPHAN', 50, ['EARTHQUAKE'], ability='SANDVEIL', hp_pct=25,
         stages={'spe': 2}),
     [('score_gt', 'AQUAJET', 'WATERFALL')]),
]

# ---------------------------------------------------------------------------
#  CORPUS_D3 — format rules (Portable 0.5.0 Phase A, 2026-09-05).
#
#  The 0.5.0 doubles table is probe-validated ONLY: the 6v6 gauntlet is singles, so
#  none of these rows can be measured in wins. That makes the probe the whole
#  evidence base for them, and it is why they are written as cards before they are
#  written as rules.
#
#  Two rows the plan listed are NOT here, because the game-side harness cannot
#  express them and AI_Harness.rb is outside this study's sources:
#    * `d_tailwind_already_active` needs a `tailwind` entry in SIDE_EFFECT_KEYS.
#    * `future_sight_not_stacked` needs a `futuresight` entry in EFFECT_KEYS.
#  `d_eq_with_grounded_partner` is also absent: CORPUS_D2's d_spread_kills_own_partner
#  already occupies that position and passes.
# ---------------------------------------------------------------------------
CORPUS_D3 = [
    # Earthquake with a Flying partner standing next to it costs nothing, so the
    # spread move should beat the single-target one against two grounded foes
    # (:2027-2038). Salamence is the airborne partner; both foes are Ground types,
    # and Dragon Claw is neutral into them, so Earthquake's only advantage is that
    # it hits twice. Asserted on the CHOICE, not on score_gt: a spread move's entry
    # in `moves` is its per-target score, and findChoosableMoves sums the two before
    # anything is chosen (the CORPUS_D2 header). MEASURED: Earthquake 35 per target
    # against Dragon Claw 38, and 63.0 against 38 once summed.
    ('d_eq_with_airborne_partner', 0,
     mon('GARCHOMP', 50, ['EARTHQUAKE', 'DRAGONCLAW'], ability='SANDVEIL'),
     mon('DONPHAN', 50, ['ROCKSLIDE'], ability='SANDVEIL'),
     [('must_choose_move_in', ['EARTHQUAKE'])],
     {'format': 'double',
      'ai2': mon('SALAMENCE', 50, ['DRAGONCLAW'], ability='MOXIE'),
      'player2': mon('QUAGSIRE', 50, ['EARTHQUAKE'], ability='DAMP')}),

    # The partner does not merely survive the spread move, it PROFITS from it:
    # Lanturn's Volt Absorb turns Discharge into a heal, which Reborn doubles the
    # score for (:2031). Thunderbolt is the same type at higher power aimed at one
    # foe, so an AI that only avoided friendly fire would still prefer Thunderbolt.
    # On the choice, not on score_gt, for the reason above (MEASURED: Discharge 103
    # per target against Thunderbolt 112, and 280.0 against 112 once summed).
    ('d_spread_into_absorbing_partner', 0,
     mon('AMPHAROS', 50, ['DISCHARGE', 'THUNDERBOLT']),
     mon('GYARADOS', 50, ['WATERFALL'], ability='MOXIE'),
     [('must_choose_move_in', ['DISCHARGE'])],
     {'format': 'double',
      'ai2': mon('LANTURN', 50, ['SURF'], ability='VOLTABSORB'),
      'player2': mon('STARMIE', 50, ['SURF'], ability='ILLUMINATE')}),

    # Lightning Rod on the FOE's partner steals every Electric move on the field
    # (:3005-3023), so Thunderbolt cannot reach the Gyarados it is 4x against and
    # Ice Beam — 2x into that same Gyarados — is the move. The strongest available
    # type matchup being the wrong answer is the point.
    ('d_redirect_by_foe_partner', 0,
     mon('AMPHAROS', 50, ['THUNDERBOLT', 'ICEBEAM']),
     mon('GYARADOS', 50, ['WATERFALL'], ability='MOXIE'),
     [('must_choose_move_in', ['ICEBEAM']),
      ('score_gt', 'ICEBEAM', 'THUNDERBOLT')],
     {'format': 'double',
      'ai2': mon('SNORLAX', 50, ['BODYSLAM'], ability='THICKFAT'),
      'player2': mon('SEAKING', 50, ['WATERFALL'], ability='LIGHTNINGROD')}),

    # The mirror case: the rod is on the AI's OWN partner, so the Electric move
    # lands on a teammate instead of a foe.
    #
    # MEASURED (stock, 2026-09-05): Thunderbolt 33 against Ice Beam 22, and the AI
    # clicks Thunderbolt. Reborn handles the FOE's rod — d_redirect_by_foe_partner
    # above passes — but not its own partner's, so the pair is a matched finding:
    # one direction of the same mechanic is implemented and the other is not.
    ('d_own_partner_rod_steals_move', 0,
     mon('AMPHAROS', 50, ['THUNDERBOLT', 'ICEBEAM']),
     mon('GYARADOS', 50, ['WATERFALL'], ability='MOXIE'),
     [('must_choose_any',)],
     {'format': 'double',
      'ai2': mon('SEAKING', 50, ['WATERFALL'], ability='LIGHTNINGROD'),
      'player2': mon('STARMIE', 50, ['SURF'], ability='ILLUMINATE')}),

    # Priority is worth less in doubles than in singles — x1.3 rather than x2
    # (:2856) — because a second foe acts whatever the order. The card only asserts
    # that the priority KO still wins; the two numbers, next to the singles pair in
    # CORPUS_V10, are the measurement.
    ('d_priority_flat_in_doubles', 0,
     mon('AZUMARILL', 50, ['AQUAJET', 'WATERFALL'], ability='HUGEPOWER'),
     mon('DONPHAN', 50, ['EARTHQUAKE'], ability='SANDVEIL', hp_pct=25,
         stages={'spe': 2}),
     [('score_gt', 'AQUAJET', 'WATERFALL')],
     {'format': 'double',
      'ai2': mon('SNORLAX', 50, ['BODYSLAM'], ability='THICKFAT'),
      'player2': mon('QUAGSIRE', 50, ['EARTHQUAKE'], ability='DAMP')}),

    # Fake Out is +115 flat on the first turn and 0 afterwards (:3528). The probe
    # builds a fresh battle, so turncount is 0 and the bonus is live; the "and 0
    # afterwards" half cannot be probed because no scenario field sets turncount.
    # Flare Blitz is the strong alternative and is neutral into Snorlax's very large
    # HP, so the +115 has to beat a genuinely good attack that is NOT a knockout.
    # A first draft put Scizor there: Flare Blitz is 4x into Bug/Steel and killed it,
    # and a knockout should beat a flinch — Portable scored Flare Blitz 714 against
    # Fake Out's 225 and was right to. Reborn preferred Fake Out at 139 to 102 only
    # because its damage score caps where Portable's lethal bonus does not.
    ('d_fakeout_turn_one', 0,
     mon('INCINEROAR', 50, ['FAKEOUT', 'FLAREBLITZ'], ability='INTIMIDATE'),
     mon('SNORLAX', 50, ['BODYSLAM'], ability='IMMUNITY'),
     [('must_choose_move_in', ['FAKEOUT'])],
     {'format': 'double',
      'ai2': mon('SNORLAX', 50, ['BODYSLAM'], ability='THICKFAT'),
      'player2': mon('GYARADOS', 50, ['WATERFALL'], ability='MOXIE')}),

    # Tailwind when the whole AI side is slower (tailwindcode:6667, x1.2 in
    # doubles). Ferrothorn (20) and Snorlax (30) are both outrun by Scizor (65) and
    # Alakazam (120), which is the position the move exists for; Power Whip is the
    # attack it has to beat. BOTH foes quarter Grass — Scizor's Bug/Steel and
    # Crobat's Poison/Flying — because the score that decides these cards is Power
    # Whip's best target, not its left one: with a resisting Scizor on the left and
    # an Alakazam on the right it still measured 84 (10 into Scizor, 84 into
    # Alakazam) against Tailwind 56 and Trick Room 70.
    ('d_tailwind_when_slower', 0,
     mon('FERROTHORN', 50, ['TAILWIND', 'POWERWHIP'], ability='IRONBARBS'),
     mon('SCIZOR', 50, ['BULLETPUNCH'], ability='SWARM'),
     [('score_gt', 'TAILWIND', 'POWERWHIP')],
     {'format': 'double',
      'ai2': mon('SNORLAX', 50, ['BODYSLAM'], ability='THICKFAT'),
      'player2': mon('CROBAT', 50, ['CROSSPOISON'], ability='INNERFOCUS')}),

    # Trick Room in the same shape (trcode:8420, x1.3 in doubles): both AI mons are
    # slow, both foes are fast, so inverting the order is worth a turn.
    ('d_trick_room_when_slower', 0,
     mon('FERROTHORN', 50, ['TRICKROOM', 'POWERWHIP'], ability='IRONBARBS'),
     mon('SCIZOR', 50, ['BULLETPUNCH'], ability='SWARM'),
     [('score_gt', 'TRICKROOM', 'POWERWHIP')],
     {'format': 'double',
      'ai2': mon('SNORLAX', 50, ['BODYSLAM'], ability='THICKFAT'),
      'player2': mon('CROBAT', 50, ['CROSSPOISON'], ability='INNERFOCUS')}),

    # Speed control as a secondary rather than a whole turn: Icy Wind is a spread
    # move that drops both foes' Speed, against Ice Beam's single target. Both foes
    # are 4x weak to Ice, so both moves do real damage; both outrun Aerodactyl at -1
    # (87), and 0.66 x their Speed is under 87, so oppstatdrop keeps the Speed row
    # and pays its x1.5 (:6270 and :6296).
    #
    # Open, because the two engines cannot be held to one assertion here and the
    # reason is structural, not a disagreement about play. Reborn: Icy Wind 43 per
    # target against Ice Beam 66, and 81 against 66 once summed -- so the CHOICE is
    # right and score_gt is false. Portable: the adapter already sums a spread move's
    # damage, so Icy Wind scores 297.95 against 293.76 -- score_gt is true -- but its
    # joint step pays a pair of single-target moves +25 for splitting targets and pays
    # a spread move nothing, which is more than the 4.19 gap, so the CHOICE is Ice
    # Beam. The hard guardrails for this row are d_tailwind_when_slower and
    # d_trick_room_when_slower, which both engines pass on score_gt.
    #
    # A first draft used -2 Speed and two bulky Water foes: Aerodactyl's 60 Special
    # Attack put Icy Wind at 2 and Ice Beam at 5, under the padded PECK filler at 15,
    # and the AI clicked Peck — the position measured nothing.
    ('d_icy_wind_speed_control', 0,
     mon('AERODACTYL', 50, ['ICYWIND', 'ICEBEAM'], stages={'spe': -1}),
     mon('GARCHOMP', 50, ['EARTHQUAKE'], ability='SANDVEIL'),
     [('must_choose_any',)],
     {'format': 'double',
      'ai2': mon('SNORLAX', 50, ['BODYSLAM'], ability='THICKFAT'),
      'player2': mon('SALAMENCE', 50, ['DRAGONCLAW'], ability='MOXIE')}),

    # Healing the PARTNER is a move that does nothing in singles and can be the best
    # move in doubles. Snorlax at 20% is the patient; Power Whip is the attack Heal
    # Pulse has to beat, and Starmie is neutral to Grass so it is a real alternative.
    ('d_heal_pulse_on_low_partner', 0,
     mon('FERROTHORN', 50, ['HEALPULSE', 'POWERWHIP'], ability='IRONBARBS'),
     mon('STARMIE', 50, ['SURF'], ability='ILLUMINATE'),
     [('must_choose_any',)],
     {'format': 'double',
      'ai2': mon('SNORLAX', 50, ['BODYSLAM'], ability='THICKFAT', hp_pct=20),
      'player2': mon('ALAKAZAM', 50, ['PSYCHIC'], ability='SYNCHRONIZE')}),

    # The doubles half of the Intimidate row is NOT here. Written and measured as
    # d_intimidate_drops_both_foes (the singles card's board plus a healthy Snorlax
    # partner and a second foe), it came back with shouldSwitch? at -40 and -30 for
    # the two actors and therefore an EMPTY switch_scores: Reborn's doubles switch
    # path does not go positive while a partner is standing, so no probe position in
    # this shape can price a doubles switch-in at all. The :11590 loop over both
    # opponents is read from the source, and the singles card above is the only
    # measurement behind the row.
]

# ---------------------------------------------------------------------------
#  CORPUS_R1 — the damage race (Portable 0.6.0 Phase A, 2026-09-05).
#
#  Every Portable rule asks a ONE-HIT question: does the next hit kill me, does my
#  next hit kill it. Nothing asks "it kills me in two, I kill it in three" — the
#  question a bulky team plays by, and bulky is where the gap sits (PORTABLE-AI-
#  DIAGNOSIS.md §1). Reborn has no explicit hits-to-KO either, but `maxdam*2 > hp`
#  gates setup (:6007), recovery (:7588) and Rest (:7667), and `pbAIfaster?` (:10051)
#  orders the final hit per move pair. These cards measure what stock does at each of
#  those places before 0.6.0 writes a rule.
#
#  THREE ENGINE FACTS THE POSITIONS ARE BUILT ON. All three were read from source and
#  then confirmed against the v0.5.0 probe artifacts; get any of them wrong and the
#  card measures a different position than the one on this page.
#
#  1. The AI DISCOUNTS ITS OWN DAMAGE BY 15% AND THE FOE'S BY NOTHING. pbRoughDamage
#     ends with `damage=(damage*random/100.0).floor`, random=85 at BESTSKILL — but
#     only under `if ai_mon_attacking` (:16833-16838), which is keyed on the battler
#     indices. So the AI's estimate of what it deals is a low roll and its estimate of
#     what is coming is a max roll. Reborn is therefore systematically PESSIMISTIC
#     about the race, and any hit count computed off these numbers inherits that.
#     (Reproducing this exactly turned a 0.83 average error into an exact match on 91
#     clean neutral rows of the 0.5.0 portable probe.)
#
#  2. ON TURN 1 THE FOE'S THREAT IS AN INVENTED MOVE, NOT ITS MOVESET. `maxdam` comes
#     from checkAIMovePlusDamage (:15671), which at HIGHSKILL tops up an incomplete
#     memory with PokeBattle_Move_FFF (:17454) — an 80 BP STAB move of each of the
#     foe's types, physical iff the foe's Attack exceeds its Special Attack. A probe
#     builds a fresh battle, `addMonToMemory` seeds an EMPTY array (:15589), and the
#     probe runs NORMAL (the harness makes a blank Game_Switches, so the Intense
#     "read the whole moveset" shortcut at :15596 is off) — so on every card here the
#     foe's listed moves are invisible to stock and only its TYPING and its higher
#     attacking stat decide what it threatens.
#     Consequence for the pair with Portable, whose adapter reads the foe's real moves
#     (Portable_AI_Adapter.rb:912): every foe below is MONO-TYPE and carries exactly
#     one attack that reproduces its own invented threat move (80 BP, STAB, right
#     category), so the two engines see the same number. Cards that deliberately break
#     this are marked.
#
#  3. THE x0.4 SETUP GATE CANNOT REACH SWORDS DANCE. :6007 requires
#     `stats[PBStats::ATTACK]==1 || stats[PBStats::SPATK]==1`, and `stats` holds the
#     number of STAGES (selfstatboost :5831). Swords Dance passes [2,0,0,0,0,0,0]
#     (:3645) and Dragon Dance [1,0,1,0,0,0,0] (:3615) — so the "I am being 2HKOed,
#     do not set up" multiplier applies to +1 moves and silently skips every +2 move.
#     race_no_setup_when_2hkoed_one_stage is the same board as its predecessor with a
#     +1 move, and the pair is the measurement.
#
#  Predicted percentages below are of the target's MAX hp and come from the model in
#  the three facts above; the probe replaces each with a MEASURED figure.
# ---------------------------------------------------------------------------
CORPUS_R1 = [
    # --- the setup gate, which is where Reborn's only hits-to-KO question lives ---
    # Espeon's invented threat (80 BP special Psychic) takes 42.6% off Garchomp, so it
    # needs three hits, and Garchomp needs three back (Strength 40.7%). Garchomp is
    # SLOWER (122 vs 130), so the one thing that could still argue against setting up
    # is the race — and Reborn's chain reaches `maxdam < hp/2` and pays setup x1.1
    # (:5993) instead. Strength is the comparator because it is 80 BP with NO
    # secondary (function 000): Iron Head would collect a flinch bonus that changes
    # sign with the speed order and would wreck the pair with the two cards below.
    ('race_setup_when_3hkoed_and_slower', 0,
     mon('GARCHOMP', 50, ['SWORDSDANCE', 'STRENGTH'], ability='SANDVEIL'),
     mon('ESPEON', 50, ['EXTRASENSORY'], ability='SYNCHRONIZE'),
     [('score_gt', 'SWORDSDANCE', 'STRENGTH')]),

    # The same foe, the same setup move, the same attack — a bulkier but much slower
    # body, so the identical invented threat is now 61.8% and kills in two. That flips
    # :5993 to the status-move branch: x0.8, and x0.3 again because Donphan has no
    # damaging move that outruns Espeon (:5999). Sand Veil is pinned so Sturdy is not
    # in the position; nothing here is an OHKO, but the Sturdy clause of the same gate
    # (:6003) reads it and the card should not depend on that being unreachable.
    ('race_no_setup_when_2hkoed_and_slower', 0,
     mon('DONPHAN', 50, ['SWORDSDANCE', 'STRENGTH'], ability='SANDVEIL'),
     mon('ESPEON', 50, ['EXTRASENSORY'], ability='SYNCHRONIZE'),
     [('score_gt', 'STRENGTH', 'SWORDSDANCE')]),

    # The card above with +2 Speed stages and nothing else changed: 70 -> 140 puts
    # Donphan in front of Espeon's 130, while the damage in both directions is
    # untouched. Speed cannot change a hit-count gap, so a rule that reads the race
    # should not move; Reborn's x0.3 clause (:5999) is a pure speed test and WILL
    # move. Open, because which of those two the reference does is the measurement —
    # and because the x0.4 gate the plan expected to isolate here cannot fire on a
    # Swords Dance at all (header fact 3), which the next card measures instead.
    ('race_setup_when_2hkoed_but_faster', 0,
     mon('DONPHAN', 50, ['SWORDSDANCE', 'STRENGTH'], ability='SANDVEIL',
         stages={'spe': 2}),
     mon('ESPEON', 50, ['EXTRASENSORY'], ability='SYNCHRONIZE'),
     [('must_choose_any',)]),

    # race_no_setup_when_2hkoed_and_slower with Dragon Dance in place of Swords Dance:
    # a +1 Attack move, so `stats[PBStats::ATTACK]==1` holds and the x0.4 branch at
    # :6007 is reachable for the first time in this corpus. Its other two conditions
    # are met too — Espeon's threat is SPECIAL and Dragon Dance leaves Special Defense
    # alone, which is the `(bestmove special && stats[SPDEF]==0)` half. The delta
    # against the Swords Dance card is the whole point: same board, same refusal
    # expected, but only this one is allowed to use the gate that was written for it.
    ('race_no_setup_when_2hkoed_one_stage', 0,
     mon('DONPHAN', 50, ['DRAGONDANCE', 'STRENGTH'], ability='SANDVEIL'),
     mon('ESPEON', 50, ['EXTRASENSORY'], ability='SYNCHRONIZE'),
     [('score_gt', 'STRENGTH', 'DRAGONDANCE')]),

    # Who lands the LAST hit, in the one shape where being faster does not decide it.
    # Garchomp at 45% outruns Snorlax 122 to 50, and Snorlax's Ice Shard is 4x into
    # Dragon/Ground: 45.9% of Garchomp's maximum, which is 102% of what it has left.
    # Snorlax moves first anyway and Garchomp is dead before its Earthquake. Stock
    # cannot see this: its invented threat is an 80 BP NORMAL move (Snorlax is
    # mono-Normal) worth 33.9%, so it reads a 2HKO with itself in front. This is the
    # ONE card that deliberately breaks the header's "listed move == invented threat"
    # rule, because the gap between the two IS the measurement — Portable's
    # incoming_by_move carries the real Ice Shard, so the two engines are looking at
    # different positions here by construction.
    ('race_no_setup_into_priority_finisher', 0,
     mon('GARCHOMP', 50, ['DRAGONDANCE', 'EARTHQUAKE'], ability='SANDVEIL',
         hp_pct=45),
     mon('SNORLAX', 50, ['ICESHARD', 'STRENGTH'], ability='IMMUNITY'),
     [('score_gt', 'EARTHQUAKE', 'DRAGONDANCE')]),

    # --- the race as a reason to stay or leave -------------------------------
    # A dead heat won on speed: Seaking needs two hits on Mamoswine (67.0%) and
    # Mamoswine needs two back (Earthquake 64.5%), and Mamoswine is faster (100 vs
    # 88), so it wins the exchange by one turn. Nothing else argues for leaving — full
    # HP, no status, no hazards — so the AI must stay. The bench exists only so that
    # `must_not_switch` is a real constraint rather than a vacuous one.
    ('race_stay_when_winning_on_speed', 0,
     mon('MAMOSWINE', 50, ['EARTHQUAKE'], ability='OBLIVIOUS'),
     mon('SEAKING', 50, ['WATERFALL'], ability='SWIFTSWIM'),
     [('must_not_switch',)],
     [mon('SNORLAX', 50, ['STRENGTH'], ability='THICKFAT')]),

    # The same question with the sign flipped, and this is the row 0.6.0's switch
    # escape reason is gated on. Donphan is at FULL HP and in no one-hit danger, but
    # Espeon 2HKOs it (61.8%) while Donphan needs three back (37.9%) — it loses the
    # race by a whole turn — and Umbreon on the bench is IMMUNE to the only thing
    # Espeon threatens. A player switches here; Reborn's shouldSwitch? (:13344) has no
    # matchup term at all, so the prediction is that it stays and switch_scores comes
    # back empty. Open, because the finding decides whether losing_damage_race ships
    # on by default or as a Radical-Red-cited experiment.
    ('race_leave_when_losing_2hko_vs_3hko', 0,
     mon('DONPHAN', 50, ['STRENGTH'], ability='SANDVEIL'),
     mon('ESPEON', 50, ['EXTRASENSORY'], ability='SYNCHRONIZE'),
     [('must_choose_any',)],
     [mon('UMBREON', 50, ['CRUNCH'], ability='SYNCHRONIZE')]),

    # --- the race as a reason to pick ONE switch-in over another -------------
    # Perish Song at count 1 is worth +220 to shouldSwitch? (:13375), which is what
    # fills switch_scores; the corpus's other switch cards buy that with an incoming
    # OHKO, and an OHKO would also swamp the thing being compared here.
    #
    # Two Mamoswine identical in every stat, type and move, differing ONLY in a held
    # Assault Vest, which pbRoughDamage reads as x1.5 Special Defense (:16735). Espeon
    # is a special attacker, so the vest turns a 2HKO (55.1%) into a 3HKO (36.7%) and
    # nothing else in either record moves. The plan's row asked for 4HKO against 2HKO;
    # no item is worth x2 Special Defense, and two DIFFERENT species would have paid
    # for the extra step with a typing or an offence difference, which is exactly what
    # this pair is built to exclude.
    ('race_switchin_prefers_bulkier_target', 0,
     mon('SKARMORY', 50, ['ROOST', 'BRAVEBIRD'], ability='KEENEYE',
         effects={'perishsong': 1}),
     mon('ESPEON', 50, ['EXTRASENSORY'], ability='SYNCHRONIZE'),
     [('switch_score_gt', 'bench0', 'bench1')],
     [mon('MAMOSWINE', 50, ['EARTHQUAKE'], ability='OBLIVIOUS', item='ASSAULTVEST'),
      mon('MAMOSWINE', 50, ['EARTHQUAKE'], ability='OBLIVIOUS')]),

    # The offensive half of the same ladder. Two Ampharos differing only in 252 Speed
    # EVs, which is enough to cross Seaking: 75 without, 107 with, against 88. Reborn
    # scales a switch-in's damage output by whether it outruns the foe (:11755-11764,
    # x1.5 against x0.75), so the fast one should win; Radical Red pays a flat +14 for
    # the same fact. EVs rather than a Speed stage because a stage is applied on the
    # FIELD and a benched candidate has none. Thunderbolt is 2x into Water, so both
    # candidates have a real offensive reason to come in and the term being measured
    # is not competing with a zero.
    ('race_switchin_outspeed_bonus', 0,
     mon('SKARMORY', 50, ['ROOST', 'BRAVEBIRD'], ability='KEENEYE',
         effects={'perishsong': 1}),
     mon('SEAKING', 50, ['WATERFALL'], ability='SWIFTSWIM'),
     [('switch_score_gt', 'bench0', 'bench1')],
     [mon('AMPHAROS', 50, ['THUNDERBOLT'], ability='STATIC', ev={'spe': 252}),
      mon('AMPHAROS', 50, ['THUNDERBOLT'], ability='STATIC')]),

    # --- priority as the tie-break of an equal race --------------------------
    # Both sides at 25%. Umbreon is slower (85 vs 88) and Seaking's hit kills it, so
    # the race is one hit each and Umbreon loses it — unless it moves first. Both of
    # its moves are Dark and both are lethal from here (Sucker Punch 104% of what
    # Seaking has left, Crunch 120%), so power, type and effectiveness are all held
    # equal and PRIORITY is the only thing separating them. Reborn should find this
    # twice over: the `priokill` flag when a capped move has priority (:598) and
    # suckercode's x1.4 for being slower (:8342).
    ('race_priority_steals_equal_race', 0,
     mon('UMBREON', 50, ['SUCKERPUNCH', 'CRUNCH'], ability='SYNCHRONIZE', hp_pct=25),
     mon('SEAKING', 50, ['WATERFALL'], ability='SWIFTSWIM', hp_pct=25),
     [('score_gt', 'SUCKERPUNCH', 'CRUNCH')]),

    # --- residual turns hits into TURNS --------------------------------------
    # Snorlax at 40% takes 30.6% a turn from Seaking, so on hits alone it survives the
    # next one. Badly poisoned at counter 3 it also loses 3/16 = 18.75% at the end of
    # that turn, and 30.6 + 18.75 > 40: it is dead this turn unless it heals, and
    # Recover (+50%) makes it live. `hpGainPerTurn` (:10112) is the term Reborn folds
    # into the same gate as maxdam, so this is the one card that asks whether the
    # reference counts TURNS rather than HITS. Thick Fat is pinned because Snorlax's
    # slot-0 Immunity would make the poison meaningless; Thick Fat touches Fire and
    # Ice only and Seaking is Water.
    ('race_residual_counts_against_me', 0,
     mon('SNORLAX', 50, ['RECOVER', 'STRENGTH'], ability='THICKFAT', hp_pct=40,
         status='poison', effects={'toxic': 3}),
     mon('SEAKING', 50, ['WATERFALL'], ability='SWIFTSWIM'),
     [('must_choose_any',)]),
]


# ---------------------------------------------------------------------------
#  CORPUS_LS — Leech Seed applicability (adapter fix, 2026-09-06).
#
#  LEECHSEED carries the "status" tag (effects.rb:58) but sets no status CONDITION:
#  the engine writes PBEffects::LeechSeed, initialised to -1 (PokeBattle_Battler.rb
#  :475). The core's only guards were the target's major status and status_immune, so
#  a seeded foe read as fresh and the move kept collecting fresh_status+25 while the
#  engine returned "failed".
#
#  The board below is the one actually observed, from set_c balance_vs_bulky 155921
#  turns 5-7: Chesnaught into Mandibuzz, LEECHSEED 125 (fresh_status+25) over
#  DRAINPUNCH 118. Seven points, so the pair is the measurement -- the fresh-target
#  card must keep Leech Seed WINNING, or the fix has simply killed the move.
#
#  The three blocked cards mirror PokeBattle_Move_0DC#pbEffect
#  (PokeBattle_MoveEffects.rb:6194): already seeded, behind a Substitute, Grass-type.
#  leechseed is a seeder INDEX applied raw by the harness (AI_Harness.rb:318), so 1
#  is the AI's own active -- the realistic "I seeded it last turn" state.
# ---------------------------------------------------------------------------
CORPUS_LS = [
    # Control. Nothing blocks the seed, so the +25 must still carry it over the
    # 118-point Drain Punch. This card fails if the fix over-blocks.
    ('leech_live_on_a_fresh_target', 0,
     mon('CHESNAUGHT', 50, ['LEECHSEED', 'DRAINPUNCH']),
     mon('MANDIBUZZ', 50, ['FOULPLAY']),
     [('score_gt', 'LEECHSEED', 'DRAINPUNCH')]),
    ('leech_no_reseed_on_a_seeded_target', 0,
     mon('CHESNAUGHT', 50, ['LEECHSEED', 'DRAINPUNCH']),
     mon('MANDIBUZZ', 50, ['FOULPLAY'], effects={'leechseed': 1}),
     [('must_not_choose_move', 'LEECHSEED'),
      ('score_gt', 'DRAINPUNCH', 'LEECHSEED')]),
    ('leech_blocked_by_a_substitute', 0,
     mon('CHESNAUGHT', 50, ['LEECHSEED', 'DRAINPUNCH']),
     mon('MANDIBUZZ', 50, ['FOULPLAY'], effects={'substitute': 50}),
     [('must_not_choose_move', 'LEECHSEED')]),
    # Grass-typing is the engine's third rejection and was never checked either. The
    # score assertion is what makes this card discriminate: must_not_choose_move alone
    # passes even on the BROKEN build, because move padding hands the AI Peck and
    # Flying is 2x into Grass, so Leech Seed loses on damage for an unrelated reason.
    # Drain Punch is neutral into Tangrowth (Fighting vs Grass) and lands at the same
    # ~119 it scores into Mandibuzz, so it is the honest comparator against the 125.
    ('leech_dead_into_a_grass_type', 0,
     mon('CHESNAUGHT', 50, ['LEECHSEED', 'DRAINPUNCH']),
     mon('TANGROWTH', 50, ['GIGADRAIN']),
     [('must_not_choose_move', 'LEECHSEED'),
      ('score_gt', 'DRAINPUNCH', 'LEECHSEED')]),
]


# ---------------------------------------------------------------------------
# 0.6.2 bugfix batch (PORTABLE-AI-REBORN.md, "Turn-by-turn readout pass on set_c").
#
# Every card is a pair: the position the readout actually showed, and a control
# alongside it that the fix must NOT change. Each card is written so it FAILS on the
# 0.6.1 build -- a card that passes either way tests nothing, which is the lesson
# leech_dead_into_a_grass_type cost to learn.
# ---------------------------------------------------------------------------
CORPUS_062 = [
    # 1. Spread moves never reach `lethal`. A spread move registers against no single
    #    battler, so the core's target lookup returns nil and Earthquake was scored
    #    against a phantom 100% target at any real target HP. Straight from the
    #    readout: offense_vs_balance 196613 t10, a faster Flygon Roosted instead of
    #    killing. Roost at 20% HP is worth +265, which no non-lethal Earthquake beats.
    ('spread_move_kills_the_dying_target', 0,
     mon('FLYGON', 50, ['EARTHQUAKE', 'ROOST'], hp_pct=20),
     mon('BISHARP', 50, ['IRONHEAD'], hp_pct=12),
     [('must_choose_move_in', ['EARTHQUAKE']),
      ('score_gt', 'EARTHQUAKE', 'ROOST')]),
    # The control the fix must not break: no kill on the board, so healing is still
    # the right call and the exported target HP has not turned Earthquake into a
    # phantom KO the other way.
    #
    # 0.6.3: Metal Claw, not Iron Head. This control is about the phantom KO, but an
    # Iron Head clears what Roost restores, and under heal_outpace a heal that only
    # delays a lost race is charged rather than credited -- which is the rule's point,
    # not this card's. A 50-BP hit keeps the heal a real save and the card measuring
    # what it was written to measure.
    ('spread_move_is_not_lethal_at_full_hp', 0,
     mon('FLYGON', 50, ['EARTHQUAKE', 'ROOST'], hp_pct=20),
     mon('BISHARP', 50, ['METALCLAW']),
     [('must_choose_move_in', ['ROOST']),
      ('score_gt', 'ROOST', 'EARTHQUAKE')]),

    # 2. A kill is a kill: pick the one that lands. Both moves KO here. Fire Blast is
    #    4x and 85% accurate, Dragon Claw is resisted and never misses, and 0.6.1
    #    handed the pick to the type chart (bulky_vs_offense 196613 t4: 649 vs 555).
    ('a_kill_is_chosen_on_accuracy_not_type', 0,
     mon('SALAMENCE', 50, ['FIREBLAST', 'DRAGONCLAW']),
     mon('FORRETRESS', 50, ['GYROBALL'], hp_pct=4),
     [('must_not_choose_move', 'FIREBLAST'),
      ('score_gt', 'DRAGONCLAW', 'FIREBLAST')]),
    # Control: nothing is lethal, so the type chart is back in charge and the 4x move
    # is right again. This is the card that fails if lethal_flat leaks into non-kills.
    ('type_still_decides_when_nothing_kills', 0,
     mon('SALAMENCE', 50, ['FIREBLAST', 'DRAGONCLAW']),
     mon('FORRETRESS', 50, ['GYROBALL']),
     [('must_choose_move_in', ['FIREBLAST']),
      ('score_gt', 'FIREBLAST', 'DRAGONCLAW')]),

    # 3. A switch-in that is dead before it moves. Three layers of Spikes, and the
    #    crushed active has a real reason to leave (-6 Attack = clear_crushed_stats).
    #    Machamp is the better matchup into Tyranitar by a wide margin and 0.6.1 sent
    #    it in to die on the hazards; Vaporeon is the body that survives to act.
    #    Readout: bulky_vs_balance 196613 t51.
    #    The active is at -3 rather than -6 on purpose. clear_crushed_stats pays +350
    #    and clear_bad_stats pays +90, and at +350 the switch outscores every move by
    #    so much that a 300-point charge cannot be seen -- two earlier drafts of this
    #    card (a second bench mon at full HP, then a resisted-matchup Miltank) both
    #    passed identically on 0.6.1 and 0.6.2 and measured nothing. Machamp is the
    #    only body available: 28% HP behind three layers of Spikes leaves 3%, which
    #    any Crunch takes on the minimum roll, so staying in is the right call.
    ('a_dying_switch_in_is_not_worth_sending', 0,
     mon('SNORLAX', 50, ['BODYSLAM'], hp_pct=60, stages={'atk': -3}),
     mon('TYRANITAR', 50, ['CRUNCH']),
     [('must_not_switch',)],
     [mon('MACHAMP', 50, ['CLOSECOMBAT'], hp_pct=28)],
     {'ai_side': {'spikes': 3}}),
    # Control: the identical board with a Machamp healthy enough to survive the entry.
    # The switch is still right, and it still goes to Machamp.
    ('the_switch_still_happens_when_the_body_lives', 0,
     mon('SNORLAX', 50, ['BODYSLAM'], hp_pct=60, stages={'atk': -3}),
     mon('TYRANITAR', 50, ['CRUNCH']),
     [('must_switch_to', 'MACHAMP')],
     [mon('MACHAMP', 50, ['CLOSECOMBAT'])],
     {'ai_side': {'spikes': 3}}),

    # 4. Wish re-clicked with a Wish already pending -- "But it failed!"
    #    (PokeBattle_MoveEffects.rb:6084). Readout: offense_vs_balance 196613 t8.
    # Pound rather than Seismic Toss as the comparator: Seismic Toss is fixed 100
    # damage and takes 62% off a Tyranitar, so it beats a live Wish on its own merits
    # and the pair would not have isolated the rule. Blissey's Pound is the weakest
    # honest alternative it has.
    ('wish_is_not_re_clicked_while_one_is_pending', 0,
     mon('BLISSEY', 50, ['WISH', 'POUND'], hp_pct=50, effects={'wish': 2}),
     mon('TYRANITAR', 50, ['CRUNCH']),
     [('must_not_choose_move', 'WISH'),
      ('score_gt', 'POUND', 'WISH')]),
    ('wish_is_live_with_none_pending', 0,
     mon('BLISSEY', 50, ['WISH', 'POUND'], hp_pct=50),
     mon('TYRANITAR', 50, ['CRUNCH']),
     [('must_choose_move_in', ['WISH']),
      ('score_gt', 'WISH', 'POUND')]),

    # 5. first_setup was decided by a memory counter that is zeroed by any non-setup
    #    action, so a +2 sweeper that attacked once was "first setting up" again
    #    (bulky_vs_offense 196613 t20). Shuckle is the comparator on purpose: Close
    #    Combat barely dents it, so a second Swords Dance wins on the bonus alone and
    #    the card turns entirely on whether the bonus is still paid.
    ('a_plus_two_sweeper_does_not_set_up_again', 0,
     mon('HERACROSS', 50, ['SWORDSDANCE', 'CLOSECOMBAT'], hp_pct=45,
         stages={'atk': 2}),
     mon('SHUCKLE', 50, ['ROCKSLIDE']),
     [('must_not_choose_move', 'SWORDSDANCE'),
      ('score_gt', 'CLOSECOMBAT', 'SWORDSDANCE')]),
    ('an_unboosted_sweeper_still_sets_up', 0,
     mon('HERACROSS', 50, ['SWORDSDANCE', 'CLOSECOMBAT'], hp_pct=45),
     mon('SHUCKLE', 50, ['ROCKSLIDE']),
     [('must_choose_move_in', ['SWORDSDANCE']),
      ('score_gt', 'SWORDSDANCE', 'CLOSECOMBAT')]),

    # 6. No memory of a failed move. Bisharp clicked a dead Sucker Punch three turns
    #    running with a guaranteed Knock Off one point behind (bulky_vs_offense 196613
    #    t22-24). effect_tantrum is Reborn's OWN "that failed" flag; last_move is what
    #    the portable memory recorded clicking.
    ('a_move_that_failed_last_turn_is_not_re_clicked', 0,
     mon('BISHARP', 50, ['SUCKERPUNCH', 'KNOCKOFF'],
         effects={'tantrum': 1}, last_move='SUCKERPUNCH'),
     mon('FORRETRESS', 50, ['GYROBALL']),
     [('must_not_choose_move', 'SUCKERPUNCH'),
      ('score_gt', 'KNOCKOFF', 'SUCKERPUNCH')]),
    # Control: same board, the move worked last turn. Sucker Punch is the better move
    # here and must stay chosen -- this is what makes the card above discriminate
    # rather than just measuring Knock Off.
    ('a_move_that_worked_last_turn_is_still_clicked', 0,
     mon('BISHARP', 50, ['SUCKERPUNCH', 'KNOCKOFF'], last_move='SUCKERPUNCH'),
     mon('FORRETRESS', 50, ['GYROBALL']),
     [('must_choose_move_in', ['SUCKERPUNCH']),
      ('score_gt', 'SUCKERPUNCH', 'KNOCKOFF')]),

    # 7. Yawn into an already-drowsy target: the engine displays "But it failed!"
    #    and returns -1 (PokeBattle_MoveEffects.rb:249) while pbCanSleep? -- the only
    #    thing 0.6.1 asked -- still says yes. Leech Seed's twin.
    ('yawn_is_dead_into_a_drowsy_target', 0,
     mon('HYPNO', 50, ['YAWN', 'ZENHEADBUTT']),
     mon('SNORLAX', 50, ['BODYSLAM'], effects={'yawn': 2}),
     [('must_not_choose_move', 'YAWN'),
      ('score_gt', 'ZENHEADBUTT', 'YAWN')]),
    # The control that makes the card above mean something: on a target that is NOT
    # drowsy, Yawn has to still be the pick. If it does not win here, the card above
    # proves nothing.
    ('yawn_is_live_against_an_alert_target', 0,
     mon('HYPNO', 50, ['YAWN', 'ZENHEADBUTT']),
     mon('SNORLAX', 50, ['BODYSLAM']),
     [('must_choose_move_in', ['YAWN']),
      ('score_gt', 'YAWN', 'ZENHEADBUTT')]),
]


CORPUS_063 = [
    # 0.6.3. Read off the Realidea shadow run's turn-by-turn readout, not proposed
    # from the source: the same three battles were losing races with a better Pokemon
    # on the bench and every switch vetoed for want of a reason.
    #
    # 1. Leave a race the actor loses, for a bench Pokemon that WINS it. Quagsire
    #    into a Calm Mind Clefable, six hits to its three, with Magnezone on the bench
    #    (team1_vs_team2 104729 t0-5). The Donphan/Espeon board of
    #    race_leave_when_losing_2hko_vs_3hko, with a bench that is actually better:
    #    Scizor resists Psychic four times over and Bug Bite two-shots Espeon. The
    #    0.6.0 flag that opened the gate for ANY bench was what stock Reborn refused
    #    on that card; this asks who is coming in.
    ('race_leave_for_a_bench_that_wins', 0,
     mon('DONPHAN', 50, ['STRENGTH'], ability='SANDVEIL'),
     mon('ESPEON', 50, ['EXTRASENSORY'], ability='SYNCHRONIZE'),
     [('must_switch_to', 'SCIZOR')],
     [mon('SCIZOR', 50, ['BUGBITE'], ability='SWARM')]),
    # The control that makes the card above mean something: the same lost race with
    # a bench that loses it too. Machamp is weak to Psychic and does nothing to Espeon
    # that Donphan does not, so leaving is just a free hit for the foe -- and the card
    # is exactly the shape stock Reborn refused. Must stay.
    ('race_stay_when_the_bench_loses_too', 0,
     mon('DONPHAN', 50, ['STRENGTH'], ability='SANDVEIL'),
     mon('ESPEON', 50, ['EXTRASENSORY'], ability='SYNCHRONIZE'),
     [('must_not_switch',)],
     [mon('MACHAMP', 50, ['CROSSCHOP'], ability='GUTS')]),

    # 2. A heal that restores less than the next hit takes, in a lost race, is not a
    #    save. Zapdos at 13% Roosted +50 into a 57% Lava Plume five turns running with
    #    Chansey on the bench (team3_vs_team1 155921 t23-28). Fire Blast so the hit
    #    clears the heal on the probe's pinned spreads too. The bench is Quagsire, not
    #    the Chansey of the readout, and that is the rule being honest rather than the
    #    card being soft: once the free entry hit is paid, Eviolite Chansey TIES
    #    Heatran on hit count (four Seismic Tosses against four Fire Blasts) and so
    #    does Slowbro (two Scalds against two Fire Blasts at 36% each), and both lose
    #    the speed tiebreak -- neither is a winner, and the probe said so both times.
    #    Earthquake is four times effective on Heatran: one hit, no tiebreak.
    ('a_heal_that_only_delays_yields_to_a_winning_bench', 0,
     mon('ZAPDOS', 50, ['ROOST', 'DISCHARGE'], hp_pct=13),
     mon('HEATRAN', 50, ['FIREBLAST'], ability='FLASHFIRE'),
     [('must_switch_to', 'QUAGSIRE')],
     [mon('QUAGSIRE', 50, ['EARTHQUAKE'], ability='UNAWARE')]),
    # The control: the same Zapdos against a hit its Roost DOES outpace. The heal is
    # still the save 0.6.2 said it was, and nothing on the bench is worth the free hit.
    ('a_heal_that_outpaces_the_hit_is_still_the_play', 0,
     mon('ZAPDOS', 50, ['ROOST', 'DISCHARGE'], hp_pct=13),
     mon('HEATRAN', 50, ['FLAMECHARGE'], ability='FLASHFIRE'),
     [('must_choose_move_in', ['ROOST'])],
     [mon('QUAGSIRE', 50, ['EARTHQUAKE'], ability='UNAWARE')]),

    # 3. "I cannot hurt it" is a reason to leave only for a body that can. In front of
    #    a Chansey every special attacker's moves are weak, so weak_current_attacks
    #    opened the gate for whoever stood there and the bench Pokemon that came in
    #    was as weak as the one that left: 168 of the 193 switch-backs against an
    #    unchanged foe in the first 0.6.3 run were Zapdos and Suicune trading places
    #    in front of one (team1_vs_team2 104729 t88-90). Machamp's Close Combat is the
    #    body that can; Alakazam's Psychic is as weak as Zapdos's Thunderbolt.
    ('weak_attacks_leave_only_for_a_body_that_hits', 0,
     mon('ZAPDOS', 50, ['THUNDERBOLT']),
     mon('CHANSEY', 50, ['SEISMICTOSS'], item='EVIOLITE'),
     [('must_switch_to', 'MACHAMP')],
     [mon('ALAKAZAM', 50, ['PSYCHIC']),
      mon('MACHAMP', 50, ['CLOSECOMBAT'], ability='GUTS')]),
    # The control: only the equally weak body on the bench, so leaving buys nothing
    # but a free Seismic Toss on the way in. Must stay.
    ('weak_attacks_stay_when_the_bench_is_as_weak', 0,
     mon('ZAPDOS', 50, ['THUNDERBOLT']),
     mon('CHANSEY', 50, ['SEISMICTOSS'], item='EVIOLITE'),
     [('must_not_switch',)],
     [mon('ALAKAZAM', 50, ['PSYCHIC'])]),
]

CORPUS_064 = [
    # 0.6.4. Two refinements of the 0.6.3 rules, read off the 0.6.3 readouts.
    #
    # 1. "I cannot hurt it" opens the gate only for a body that BREAKS the wall: two
    #    whole hits fewer than the actor and no more than four of its own. 0.6.3 asked
    #    for 10% and got 62 switch-backs from bodies that cleared the line on the bench
    #    and not on the field. Alakazam has nothing for Umbreon (Psychic is immune) and
    #    Umbreon has nothing for anyone, so no race is in play and only this reason is.
    #    Four moves each side so no filler pads the set: Politoed's Scald is a fifth of
    #    Umbreon and clears the line; Machamp's Close Combat is the body that breaks it.
    ('no_effective_move_needs_a_body_that_breaks_the_wall', 0,
     mon('ALAKAZAM', 50, ['PSYCHIC', 'CALMMIND', 'RECOVER', 'SUBSTITUTE']),
     mon('UMBREON', 50, ['TOXIC', 'WISH', 'PROTECT', 'MOONLIGHT'], ability='SYNCHRONIZE'),
     [('must_switch_to', 'MACHAMP')],
     [mon('POLITOED', 50, ['SCALD', 'ICEBEAM', 'HYPNOSIS', 'PROTECT'], ability='DAMP'),
      mon('MACHAMP', 50, ['CLOSECOMBAT', 'BULLETPUNCH', 'KNOCKOFF', 'ICEPUNCH'],
          ability='GUTS')]),
    # The control: only the line-clearer on the bench. 0.6.3 leaves for it, and
    # Politoed in front of Umbreon is Zapdos in front of Chansey -- a body as weak as
    # the one that left, one switch-back from now. Must stay.
    ('a_body_that_only_clears_the_line_is_not_worth_the_free_turn', 0,
     mon('ALAKAZAM', 50, ['PSYCHIC', 'CALMMIND', 'RECOVER', 'SUBSTITUTE']),
     mon('UMBREON', 50, ['TOXIC', 'WISH', 'PROTECT', 'MOONLIGHT'], ability='SYNCHRONIZE'),
     [('must_not_switch',)],
     [mon('POLITOED', 50, ['SCALD', 'ICEBEAM', 'HYPNOSIS', 'PROTECT'], ability='DAMP')]),

    # 2. Every switch candidate is graded on who lands the last hit once it is in.
    #    The readout case (team3_vs_team2 155921 t29) was Scizor sent into a Heatran
    #    that kills it first with Slowbro on the bench -- a post-KO replacement, which
    #    the probe cannot pose, so the card poses the same choice with a reason to
    #    leave that is not the race: Zapdos is Yawned. Scald two-shots Heatran and
    #    Fire Blast is resisted; Bug Bite is resisted and Fire Blast is four times
    #    effective. Passes at 0.6.3 too (the entry cost already says so) -- this is
    #    the fixture for the complaint. The graded term itself ships OFF (it cost
    #    wins on both gauntlets; see Model::DEFAULT_CONFIG), so the card holds the
    #    behaviour, not the term.
    ('a_reason_to_leave_does_not_send_in_the_body_that_dies_first', 0,
     mon('ZAPDOS', 50, ['DISCHARGE', 'HEATWAVE'], effects={'yawn': 2}),
     mon('HEATRAN', 50, ['FIREBLAST'], ability='FLASHFIRE'),
     [('must_switch_to', 'SLOWBRO')],
     [mon('SCIZOR', 50, ['BUGBITE', 'BULLETPUNCH', 'SWORDSDANCE', 'ROOST'],
          ability='TECHNICIAN'),
      mon('SLOWBRO', 50, ['SCALD', 'PSYCHIC', 'SLACKOFF', 'CALMMIND'],
          ability='REGENERATOR')]),

    # 3. The entry damage is part of the race. The arithmetic was in candidate_race
    #    at 0.6.3; this pair is the proof that was asked for. Flare Blitz knocks
    #    Zapdos out at 13% and out-damages its Roost, so the race is lost and the heal
    #    only delays; Charizard's Earthquake two-shots Heatran (Flash Fire takes its
    #    fire) and Flare Blitz, resisted, is a third of Charizard. Off rocks Charizard
    #    wins by one hit; on rocks it comes in at half and loses by one. Tuned on both
    #    engines' rankings: Realidea's chart has Steel resisting Dark, and its
    #    Charizard hits half again as hard as Reborn's, so a neutral move that
    #    three-shots on one engine five-shots on the other.
    ('a_winning_bench_body_is_still_a_winner_off_the_rocks', 0,
     mon('ZAPDOS', 50, ['ROOST', 'DISCHARGE'], hp_pct=13),
     mon('HEATRAN', 50, ['FLAREBLITZ'], ability='FLASHFIRE'),
     [('must_switch_to', 'CHARIZARD')],
     [mon('CHARIZARD', 50, ['EARTHQUAKE', 'AIRSLASH', 'ROOST', 'PROTECT'],
          ability='BLAZE')]),
    ('the_rocks_turn_the_same_body_into_a_loser', 0,
     mon('ZAPDOS', 50, ['ROOST', 'DISCHARGE'], hp_pct=13),
     mon('HEATRAN', 50, ['FLAREBLITZ'], ability='FLASHFIRE'),
     [('must_not_switch',)],
     [mon('CHARIZARD', 50, ['EARTHQUAKE', 'AIRSLASH', 'ROOST', 'PROTECT'],
          ability='BLAZE')],
     {'ai_side': {'stealthrock': 1}}),
]

# ---------------------------------------------------------------------------
# 0.6.5 -- the party x party damage matrix and its two consumers.
#
# REALIDEA ONLY. Both rules read snapshot["matrix"], which only the Realidea adapter
# builds; on Reborn they are inert by construction and these cards would grade a build
# against a rule it does not have. `engine: 'realidea'` keeps them out of the Reborn
# corpus, printed at generation time rather than skipped in silence.
#
# Each card has to FAIL with its key off and pass with it on -- that pair is what
# makes it evidence rather than decoration -- so the numbers below are tuned against
# the probe's own matrix verdicts and rankings, not calculated on paper. That is the
# 0.6.4 lesson (PORTABLE-AI-REALIDEA.md, "Corpus tuning note"): this engine's chart
# has Steel resisting Dark and its damage rolls differ from Reborn's by up to half.
CORPUS_065 = [
    # 1. The shadow case, posed as a card. Stock spent its only answer to their Scizor
    #    into an Azumarill it loses to (team4_vs_team1 130363, stock arm, a 19-turn
    #    loss). The probe cannot pose a post-KO replacement, so the reason to leave is
    #    the same Yawn device the 0.6.4 card uses: Zapdos is drowsy and both bench
    #    bodies are legal. Magnezone loses to the Heatran in front and is the only
    #    thing here that beats their benched Gyarados; Slowbro beats the Heatran and
    #    answers nothing else. 0.6.4 sends Magnezone.
    ('the_only_answer_to_a_bench_foe_is_not_spent_into_a_foe_it_loses_to', 0,
     mon('ZAPDOS', 50, ['DISCHARGE', 'HEATWAVE'], effects={'yawn': 2}),
     mon('HEATRAN', 50, ['FIREBLAST', 'EARTHPOWER'], ability='FLASHFIRE'),
     [('must_switch_to', 'SLOWBRO')],
     [mon('MAGNEZONE', 50, ['THUNDERBOLT', 'FLASHCANNON', 'VOLTSWITCH', 'SUBSTITUTE'],
          ability='MAGNETPULL'),
      mon('SLOWBRO', 50, ['SCALD', 'PSYCHIC', 'SLACKOFF', 'CALMMIND'],
          ability='REGENERATOR')],
     {'engine': 'realidea',
      'player_bench': [mon('GYARADOS', 50, ['WATERFALL', 'EARTHQUAKE', 'ICEFANG',
                                            'DRAGONDANCE'], ability='INTIMIDATE')]}),

    # 2. The reserve half of the same rule, and the case it was written for: a forced
    #    choice between two bodies that BOTH handle what is in front. Tyranitar and
    #    Slowbro each beat the Heatran; only Tyranitar beats their benched Latias. The
    #    turn does not need Tyranitar in particular, so it is kept.
    ('a_forced_choice_keeps_the_body_that_is_the_only_answer_later', 0,
     mon('ZAPDOS', 50, ['DISCHARGE', 'HEATWAVE'], effects={'yawn': 2}),
     mon('HEATRAN', 50, ['FIREBLAST', 'EARTHPOWER'], ability='FLASHFIRE'),
     [('must_switch_to', 'SLOWBRO')],
     [mon('TYRANITAR', 50, ['STONEEDGE', 'CRUNCH', 'PURSUIT', 'FIREPUNCH'],
          ability='SANDSTREAM'),
      mon('SLOWBRO', 50, ['SCALD', 'PSYCHIC', 'SLACKOFF', 'CALMMIND'],
          ability='REGENERATOR')],
     {'engine': 'realidea',
      'player_bench': [mon('LATIAS', 50, ['DRACOMETEOR', 'PSYSHOCK', 'ROOST',
                                          'HEALINGWISH'], ability='LEVITATE')]}),

    # 3. A boost is worth the cells it flips. Scizor at +2 stops losing to the bodies
    #    on their bench, and the Clefable in front gives it the turn to buy them.
    ('a_boost_that_flips_the_bench_is_worth_the_turn', 0,
     mon('SCIZOR', 50, ['BUGBITE', 'BULLETPUNCH', 'SWORDSDANCE', 'ROOST'],
         ability='TECHNICIAN'),
     mon('CLEFABLE', 50, ['MOONBLAST', 'SOFTBOILED', 'CALMMIND', 'THUNDERWAVE'],
         ability='MAGICGUARD'),
     [('must_choose_move_in', ['SWORDSDANCE'])],
     [],
     {'engine': 'realidea',
      'player_bench': [mon('LATIAS', 50, ['DRACOMETEOR', 'PSYSHOCK', 'ROOST'],
                           ability='LEVITATE'),
                       mon('TYRANITAR', 50, ['STONEEDGE', 'CRUNCH', 'PURSUIT'],
                           ability='SANDSTREAM')]}),
    # The control, and the whole point of the rule: the same boost against a party it
    # changes nothing about. Skarmory walls Scizor at any Attack stage and Heatran
    # removes it whatever it is holding, so the flat 55 was paying for a wasted turn.
    ('a_boost_that_flips_nothing_is_not_a_free_55', 0,
     mon('SCIZOR', 50, ['BUGBITE', 'BULLETPUNCH', 'SWORDSDANCE', 'ROOST'],
         ability='TECHNICIAN'),
     mon('SKARMORY', 50, ['BRAVEBIRD', 'ROOST', 'SPIKES', 'WHIRLWIND'],
         ability='STURDY'),
     [('must_not_choose_move', 'SWORDSDANCE')],
     [],
     {'engine': 'realidea',
      'player_bench': [mon('HEATRAN', 50, ['FIREBLAST', 'EARTHPOWER', 'TOXIC'],
                           ability='FLASHFIRE')]}),
]

CORPUS = (CORPUS_V1 + CORPUS_V2 + CORPUS_V3 + CORPUS_V4 + CORPUS_V5
          + CORPUS_V6 + CORPUS_V7 + CORPUS_V8 + CORPUS_V9 + CORPUS_V10
          + CORPUS_D1 + CORPUS_D2 + CORPUS_D3 + CORPUS_R1 + CORPUS_LS
          + CORPUS_062 + CORPUS_063 + CORPUS_064 + CORPUS_065)

# Values a scenario's extra dict may carry; the generator validates so a typo
# fails here instead of silently emitting a key no probe reads.
WEATHER_NAMES = {'rain', 'sun', 'sand', 'hail'}
SIDE_EFFECT_KEYS = {'spikes', 'toxicspikes', 'stealthrock', 'reflect', 'lightscreen'}
# Battler effects a mon's effects= dict may carry (validated the same way).
EFFECT_NAMES = {'perishsong', 'leechseed', 'confusion', 'toxic', 'yawn',
                'substitute', 'curse', 'choiceband', 'wish', 'tantrum'}
# Keys the trailing extra dict may carry. Validated for the same reason the values
# are: an unknown key used to be dropped in silence, so a card written with a typo'd
# or not-yet-implemented key probed a DIFFERENT position than the one on the page and
# still reported PASS.
EXTRA_KEYS = {'weather', 'ai_side', 'player_side', 'format', 'ai2', 'player2',
              'player_bench', 'engine'}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--pbs', help='plaintext PBS dir; required for --engine reborn')
    ap.add_argument('--engine', choices=['reborn', 'hegemony'], default='reborn',
                    help='reborn = v16 numeric IDs from PBS; '
                         'hegemony = v19 symbols, resolved by the engine')
    ap.add_argument('--install',
                    help='name of the install this corpus is for (e.g. realidea). A '
                         'card carrying an "engine" key is emitted only for the '
                         'install it names; every other card is emitted always. Both '
                         'Reborn and Realidea resolve IDs the v16 way (--engine '
                         'reborn), so the ID scheme cannot tell them apart, and a '
                         'card that pins a rule only one adapter exports would '
                         'otherwise be graded against a build that never had it.')
    ap.add_argument('--out-engine', required=True)
    ap.add_argument('--out-json', required=True)
    ap.add_argument('--drop-unresolved', action='store_true',
                    help='drop each scenario whose names this PBS cannot resolve, '
                         'instead of failing the whole run. For porting the corpus to '
                         'an older engine: Realidea is v16 and has no Heavy-Duty Boots '
                         'or Clear Amulet, so the cards built on them cannot exist '
                         'there. Every dropped scenario is printed with its reason, and '
                         'neither output file mentions it -- the emitted corpus and the '
                         'json stay the same corpus.')
    a = ap.parse_args()

    # v16 addresses everything by integer and ships plaintext PBS to resolve against.
    # v19 addresses everything by symbol, and Hegemony ships no PBS folder at all — only
    # compiled .dat. So names pass through verbatim and the engine validates them, raising
    # per scenario (AI_Probe.rb build_mon) rather than failing the whole run.
    if a.engine == 'reborn':
        if not a.pbs:
            ap.error('--pbs is required for --engine reborn')
        mv, sp, it, ab = load_pbs(a.pbs)
    else:
        mv = sp = it = ab = None
    # Unresolved names for the scenario being emitted right now. Merged into `missing`
    # only when the scenario is actually kept, so --drop-unresolved does not leave the
    # run failing on a name that only the dropped cards used.
    scenario_missing = set()
    missing = set()
    skipped_install = []

    def state_parts(m):
        """Trailing state fields (hp/status/stages/evs/effects/pp)."""
        parts = []
        if m['hp_pct'] is not None:
            parts.append('hp_pct:%g' % m['hp_pct'])
        if m['status']:
            parts.append('status:' + m['status'])
        for k, v in (m['stages'] or {}).items():
            parts.append('stage_%s:%d' % (k, v))
        for k, v in (m.get('ev') or {}).items():
            parts.append('ev_%s:%d' % (k, v))
        for k, v in (m.get('effects') or {}).items():
            if k not in EFFECT_NAMES:
                scenario_missing.add('effect:' + k)
            elif k == 'choiceband':
                # Value is a move NAME: numeric id on v16, symbol name on v19
                # (the engines store the locked move in the same effect slot).
                if a.engine == 'hegemony':
                    parts.append('effect_choiceband:%s' % v)
                elif v in mv:
                    parts.append('effect_choiceband:%d' % mv[v])
                else:
                    scenario_missing.add('move:' + str(v))
            else:
                parts.append('effect_%s:%d' % (k, v))
        if m.get('pp_all') is not None:
            parts.append('pp_all:%d' % m['pp_all'])
        if m.get('last_move'):
            # Same treatment as effect_choiceband: numeric id on v16, name on v19.
            if a.engine == 'hegemony':
                parts.append('last_move:%s' % m['last_move'])
            elif m['last_move'] in mv:
                parts.append('last_move:%d' % mv[m['last_move']])
            else:
                scenario_missing.add('move:' + str(m['last_move']))
        return parts

    def mon_line(m):
        if a.engine == 'hegemony':
            parts = ['species:%s' % m['species'], 'level:%d' % m['level']]
            if m['moves']:
                parts.append('moves:' + ','.join(m['moves']))
            if m['item']:
                parts.append('item:%s' % m['item'])
            if m['ability']:
                parts.append('ability:%s' % m['ability'])
            if m.get('nature'):
                parts.append('nature:%s' % m['nature'])
            return '|'.join(parts + state_parts(m))
        if m['species'] not in sp:
            scenario_missing.add('species:' + m['species'])
            return None
        parts = ['species:%d' % sp[m['species']], 'level:%d' % m['level']]
        ids = []
        for name in m['moves']:
            if name not in mv:
                scenario_missing.add('move:' + name)
            else:
                ids.append(mv[name])
        if ids:
            parts.append('moves:' + ','.join(str(i) for i in ids))
        if m['item']:
            if m['item'] not in it:
                scenario_missing.add('item:' + m['item'])
            else:
                parts.append('item:%d' % it[m['item']])
        if m['ability']:
            # Reborn's setAbility takes a SLOT INDEX ([ab0, ab1, hidden]), so resolve
            # the name against this species' PBS ability slots.
            slots = ab.get(m['species'], [None, None, None])
            if m['ability'] in slots:
                parts.append('ability:%d' % slots.index(m['ability']))
            else:
                scenario_missing.add('ability:%s on %s (has %s)'
                            % (m['ability'], m['species'],
                               ','.join(s for s in slots if s)))
        if m.get('nature'):
            if m['nature'] in NATURE_IDS:
                parts.append('nature:%d' % NATURE_IDS[m['nature']])
            else:
                scenario_missing.add('nature:' + m['nature'])
        return '|'.join(parts + state_parts(m))

    lines, corpus_json = [], []
    dropped = []
    for entry in CORPUS:
        scenario_missing.clear()
        block = []
        sid, field, ai, pl, asserts = entry[0], entry[1], entry[2], entry[3], entry[4]
        # Optional trailing elements, order-free: a list is the AI bench, a dict
        # is battle-level extra state (weather / ai_side / player_side).
        bench, extra = [], {}
        for x in entry[5:]:
            if isinstance(x, list):
                bench = x
            elif isinstance(x, dict):
                extra = x
        for k in extra:
            if k not in EXTRA_KEYS:
                scenario_missing.add('extra key:%s in %s' % (k, sid))
        if extra.get('weather') and extra['weather'] not in WEATHER_NAMES:
            scenario_missing.add('weather:%s in %s' % (extra['weather'], sid))
        for sk in ('ai_side', 'player_side'):
            for k in (extra.get(sk) or {}):
                if k not in SIDE_EFFECT_KEYS:
                    scenario_missing.add('side_effect:%s in %s' % (k, sid))
        # A card written for one install only. Not a name this PBS cannot resolve
        # and not an engine refusal at probe time -- a statement that the behaviour
        # under test exists on one adapter, so grading the other against it would be
        # asking a build about a rule it does not have.
        wanted = extra.get('engine')
        if wanted and wanted != a.install:
            skipped_install.append((sid, wanted))
            continue
        fmt = extra.get('format', 'single')
        if fmt not in ('single', 'double'):
            scenario_missing.add('format:%s in %s' % (fmt, sid))
        ai2, pl2 = extra.get('ai2'), extra.get('player2')
        # Both halves of the field or neither: a 2v1 would be a different battle
        # type that neither probe sets up, and silently dropping the odd one out
        # would probe a position nobody wrote.
        if fmt == 'double' and (ai2 is None or pl2 is None):
            scenario_missing.add('format=double needs ai2 and player2 in %s' % sid)
        if fmt == 'single' and (ai2 or pl2):
            scenario_missing.add('ai2/player2 given without format=double in %s' % sid)
        # AI side only. The player's moveset is what the AI reads to build its threat
        # model, and the assertions were calibrated against it — padding it would change
        # the position rather than just the AI's self-classification.
        ai = pad_to_four(ai)
        if ai2:
            ai2 = pad_to_four(ai2)
        bench = [pad_to_four(b) for b in bench]
        block.append('[%s]' % sid)
        block.append('field=%d' % field)
        if fmt != 'single':
            block.append('format=%s' % fmt)
        if extra.get('weather'):
            block.append('weather=%s' % extra['weather'])
        for sk in ('ai_side', 'player_side'):
            d = extra.get(sk)
            if d:
                block.append('%s=%s' % (sk, '|'.join('%s:%d' % (k, v)
                                                     for k, v in d.items())))
        block.append('ai=' + (mon_line(ai) or ''))
        if ai2:
            block.append('ai2=' + (mon_line(ai2) or ''))
        for b in bench:
            block.append('ai_bench=' + (mon_line(b) or ''))
        block.append('player=' + (mon_line(pl) or ''))
        # Player actives and bench are NOT padded — their movesets are the AI's
        # threat model, not a role-classifier input.
        if pl2:
            block.append('player2=' + (mon_line(pl2) or ''))
        for b in (extra.get('player_bench') or []):
            block.append('player_bench=' + (mon_line(b) or ''))
        block.append('')
        # move_ids covers BOTH AI actives: a doubles assertion can name a move that
        # only the right-hand battler knows, and check_scenarios/ai_diff resolve
        # every name through this one map.
        all_ai_moves = list(ai['moves']) + (list(ai2['moves']) if ai2 else [])
        if scenario_missing:
            if a.drop_unresolved:
                dropped.append((sid, sorted(scenario_missing)))
                continue
            missing |= scenario_missing
        lines.extend(block)
        corpus_json.append({
            'id': sid, 'field': field, 'format': fmt,
            'weather': extra.get('weather'),
            'ai_side': extra.get('ai_side') or {},
            'player_side': extra.get('player_side') or {},
            'ai_moves': ai['moves'], 'ai_species': ai['species'],
            'player_species': pl['species'],
            'ai2_moves': (ai2['moves'] if ai2 else None),
            'ai2_species': (ai2['species'] if ai2 else None),
            'player2_species': (pl2['species'] if pl2 else None),
            # AI party in the order build_party assembles it (AI_Harness.rb:362):
            # active, active2 if doubles, then the bench. switch_score_gt needs it to
            # turn a species or benchN reference into an index into switch_scores,
            # which the engine emits as a bare array of numbers.
            'ai_party_species': ([ai['species']]
                                 + ([ai2['species']] if ai2 else [])
                                 + [b['species'] for b in bench]),
            'ai_actives': (2 if ai2 else 1),
            # Maps the canonical internal name to whatever this engine calls it, so
            # ai_diff.py can canonicalise both sides back to names before comparing.
            # v19 is its own identity map.
            'move_ids': ({n: n for n in all_ai_moves} if a.engine == 'hegemony'
                         else {n: mv.get(n) for n in all_ai_moves}),
            'assertions': [list(x) for x in asserts],
        })

    # Hard failure, and nothing is written. Every one of these means the emitted
    # corpus would not be the corpus on the page -- an unresolved ability silently
    # leaves the mon on slot 0, an unresolved item leaves it bare -- and the probe
    # would then grade a position nobody wrote. Previously this printed a WARNING
    # and exited 0, so a CI-style `make_scenarios && Game.exe && check_scenarios`
    # chain ran straight past it.
    if missing:
        raise SystemExit('unresolved names (nothing written): '
                         + ', '.join(sorted(missing)))

    # Loud on purpose. A dropped card is a card this engine cannot be asked about, and
    # the applicable-assertion count in the docs has to be read off what was written.
    for sid, wanted in skipped_install:
        print('not for this install (%s only): %s' % (wanted, sid))
    for sid, reasons in dropped:
        print('dropped %s: %s' % (sid, ', '.join(reasons)))
    if dropped:
        print('dropped %d of %d scenarios this PBS cannot build'
              % (len(dropped), len(CORPUS)))

    with open(a.out_engine, 'w', encoding='utf-8', newline='\n') as f:
        f.write('# generated by make_scenarios.py — do not hand-edit\n')
        f.write('\n'.join(lines))
    with open(a.out_json, 'w', encoding='utf-8') as f:
        json.dump(corpus_json, f, indent=1)
    print('wrote %d scenarios -> %s (+ %s)' % (len(corpus_json), a.out_engine, a.out_json))


if __name__ == '__main__':
    main()
