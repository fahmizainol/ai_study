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
        pp_all=None):
    """ability/nature are NAMES ('WATERABSORB', 'ADAMANT'); ev is {'atk': 252, ...}.
    Probes pin nature=HARDY and ability slot 0 when unspecified, so these are only
    needed when a scenario depends on a specific one (e.g. an absorb-ability target
    whose species has two possible abilities).

    effects is {name: value} of battler effects applied on-field — see
    EFFECT_NAMES. Values are ints (perish/toxic counters, sub HP, seeder index
    for leechseed where 0 = the player active, 1 = curse on) EXCEPT choiceband,
    whose value is the locked move's NAME (resolved per engine). pp_all sets
    every move's PP (0 = the +200 forced-out trigger)."""
    return {'species': species, 'level': level, 'moves': list(moves), 'item': item,
            'hp_pct': hp_pct, 'status': status, 'stages': stages or {},
            'ability': ability, 'nature': nature, 'ev': ev or {},
            'effects': effects or {}, 'pp_all': pp_all}


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
    ('heal_at_low_hp', 0,
     mon('BLISSEY', 50, ['SOFTBOILED', 'DAZZLINGGLEAM'], hp_pct=12),
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

CORPUS = (CORPUS_V1 + CORPUS_V2 + CORPUS_V3 + CORPUS_V4 + CORPUS_V5
          + CORPUS_V6 + CORPUS_V7)

# Values a scenario's extra dict may carry; the generator validates so a typo
# fails here instead of silently emitting a key no probe reads.
WEATHER_NAMES = {'rain', 'sun', 'sand', 'hail'}
SIDE_EFFECT_KEYS = {'spikes', 'toxicspikes', 'stealthrock', 'reflect', 'lightscreen'}
# Battler effects a mon's effects= dict may carry (validated the same way).
EFFECT_NAMES = {'perishsong', 'leechseed', 'confusion', 'toxic', 'yawn',
                'substitute', 'curse', 'choiceband'}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--pbs', help='plaintext PBS dir; required for --engine reborn')
    ap.add_argument('--engine', choices=['reborn', 'hegemony'], default='reborn',
                    help='reborn = v16 numeric IDs from PBS; '
                         'hegemony = v19 symbols, resolved by the engine')
    ap.add_argument('--out-engine', required=True)
    ap.add_argument('--out-json', required=True)
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
    missing = set()

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
                missing.add('effect:' + k)
            elif k == 'choiceband':
                # Value is a move NAME: numeric id on v16, symbol name on v19
                # (the engines store the locked move in the same effect slot).
                if a.engine == 'hegemony':
                    parts.append('effect_choiceband:%s' % v)
                elif v in mv:
                    parts.append('effect_choiceband:%d' % mv[v])
                else:
                    missing.add('move:' + str(v))
            else:
                parts.append('effect_%s:%d' % (k, v))
        if m.get('pp_all') is not None:
            parts.append('pp_all:%d' % m['pp_all'])
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
            missing.add('species:' + m['species'])
            return None
        parts = ['species:%d' % sp[m['species']], 'level:%d' % m['level']]
        ids = []
        for name in m['moves']:
            if name not in mv:
                missing.add('move:' + name)
            else:
                ids.append(mv[name])
        if ids:
            parts.append('moves:' + ','.join(str(i) for i in ids))
        if m['item']:
            if m['item'] not in it:
                missing.add('item:' + m['item'])
            else:
                parts.append('item:%d' % it[m['item']])
        if m['ability']:
            # Reborn's setAbility takes a SLOT INDEX ([ab0, ab1, hidden]), so resolve
            # the name against this species' PBS ability slots.
            slots = ab.get(m['species'], [None, None, None])
            if m['ability'] in slots:
                parts.append('ability:%d' % slots.index(m['ability']))
            else:
                missing.add('ability:%s on %s (has %s)'
                            % (m['ability'], m['species'],
                               ','.join(s for s in slots if s)))
        if m.get('nature'):
            if m['nature'] in NATURE_IDS:
                parts.append('nature:%d' % NATURE_IDS[m['nature']])
            else:
                missing.add('nature:' + m['nature'])
        return '|'.join(parts + state_parts(m))

    lines, corpus_json = [], []
    for entry in CORPUS:
        sid, field, ai, pl, asserts = entry[0], entry[1], entry[2], entry[3], entry[4]
        # Optional trailing elements, order-free: a list is the AI bench, a dict
        # is battle-level extra state (weather / ai_side / player_side).
        bench, extra = [], {}
        for x in entry[5:]:
            if isinstance(x, list):
                bench = x
            elif isinstance(x, dict):
                extra = x
        if extra.get('weather') and extra['weather'] not in WEATHER_NAMES:
            missing.add('weather:%s in %s' % (extra['weather'], sid))
        for sk in ('ai_side', 'player_side'):
            for k in (extra.get(sk) or {}):
                if k not in SIDE_EFFECT_KEYS:
                    missing.add('side_effect:%s in %s' % (k, sid))
        # AI side only. The player's moveset is what the AI reads to build its threat
        # model, and the assertions were calibrated against it — padding it would change
        # the position rather than just the AI's self-classification.
        ai = pad_to_four(ai)
        bench = [pad_to_four(b) for b in bench]
        lines.append('[%s]' % sid)
        lines.append('field=%d' % field)
        if extra.get('weather'):
            lines.append('weather=%s' % extra['weather'])
        for sk in ('ai_side', 'player_side'):
            d = extra.get(sk)
            if d:
                lines.append('%s=%s' % (sk, '|'.join('%s:%d' % (k, v)
                                                     for k, v in d.items())))
        lines.append('ai=' + (mon_line(ai) or ''))
        for b in bench:
            lines.append('ai_bench=' + (mon_line(b) or ''))
        lines.append('player=' + (mon_line(pl) or ''))
        # Player bench mons are NOT padded — like the player active, their
        # movesets are the AI's threat model, not a role-classifier input.
        for b in (extra.get('player_bench') or []):
            lines.append('player_bench=' + (mon_line(b) or ''))
        lines.append('')
        corpus_json.append({
            'id': sid, 'field': field,
            'weather': extra.get('weather'),
            'ai_side': extra.get('ai_side') or {},
            'player_side': extra.get('player_side') or {},
            'ai_moves': ai['moves'], 'ai_species': ai['species'],
            'player_species': pl['species'],
            # Maps the canonical internal name to whatever this engine calls it, so
            # ai_diff.py can canonicalise both sides back to names before comparing.
            # v19 is its own identity map.
            'move_ids': ({n: n for n in ai['moves']} if a.engine == 'hegemony'
                         else {n: mv.get(n) for n in ai['moves']}),
            'assertions': [list(x) for x in asserts],
        })

    if missing:
        print('WARNING unresolved names: ' + ', '.join(sorted(missing)))

    with open(a.out_engine, 'w', encoding='utf-8', newline='\n') as f:
        f.write('# generated by make_scenarios.py — do not hand-edit\n')
        f.write('\n'.join(lines))
    with open(a.out_json, 'w', encoding='utf-8') as f:
        json.dump(corpus_json, f, indent=1)
    print('wrote %d scenarios -> %s (+ %s)' % (len(CORPUS), a.out_engine, a.out_json))


if __name__ == '__main__':
    main()
