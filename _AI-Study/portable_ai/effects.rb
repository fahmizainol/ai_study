# Canonical move knowledge keyed by internal move ID, never by Essentials function code.
# Adapters convert PBMoves::FOO / GameData IDs to the uppercase String "FOO".

module PortableAI
  module Effects
    TABLE = {}

    # Tags accumulate: a move may be listed by more than one call (Explosion is both
    # a spread move and a self-KO), so the table is order-independent.
    def self.add(ids, tags)
      ids.each do |id|
        known = TABLE[id] || []
        merged = known.clone
        tags.each { |tag| merged << tag if !merged.include?(tag) }
        TABLE[id] = merged
      end
    end

    # "heal" alone is the flat half-HP recovery the core assumes. The two refinements
    # exist because the 0.4.0 heal gate asks whether healing outruns the incoming hit,
    # which needs the amount: Rest refills completely, and the weather heals pay only
    # a quarter in sand or hail.
    add(%w[RECOVER ROOST SOFTBOILED MILKDRINK SLACKOFF
           HEALORDER SHOREUP], ["heal"])
    add(%w[MOONLIGHT SYNTHESIS MORNINGSUN], ["heal", "heal_weather"])
    add(%w[REST], ["heal", "heal_full", "self_sleep"])
    add(%w[WISH], ["delayed_heal"])
    add(%w[PAINSPLIT], ["variable_heal"])

    # Defensive setup was missing entirely: the list was offensive boosts only, so
    # Iron Defense and Amnesia were scored as plain unknown status moves. Curse is
    # here for the non-Ghost form; the adapter's own type check keeps the Ghost form
    # (which costs half the user's HP) out.
    add(%w[SWORDSDANCE NASTYPLOT DRAGONDANCE QUIVERDANCE CALMMIND
           BULKUP COIL SHELLSMASH GEOMANCY TAILGLOW
           AGILITY ROCKPOLISH AUTOTOMIZE WORKUP GROWTH
           IRONDEFENSE AMNESIA COSMICPOWER ACIDARMOR BARRIER STOCKPILE
           HONECLAWS CURSE DEFENDORDER], ["setup"])
    add(%w[BELLYDRUM], ["setup", "hp_cost_half"])

    # 0.6.5. WHAT each setup move actually raises, so a boost can be priced by what
    # it changes rather than by a flat bonus (Core.setup_matrix_value). Every id
    # carrying the "setup" tag above has a row here and a test asserts it, because a
    # missing row silently falls back to the flat 55 and nothing would say so.
    #
    # Stat keys are the core's own short names, not engine constants: "atk", "def",
    # "spa", "spd", "speed". Drops are negative -- Shell Smash pays two defences for
    # its three boosts and Curse pays speed, and a rule that only read the boosts
    # would call both of them free.
    SETUP_STAGES = {
      "SWORDSDANCE"  => { "atk" => 2 },
      "NASTYPLOT"    => { "spa" => 2 },
      "TAILGLOW"     => { "spa" => 3 },
      "DRAGONDANCE"  => { "atk" => 1, "speed" => 1 },
      "QUIVERDANCE"  => { "spa" => 1, "spd" => 1, "speed" => 1 },
      "CALMMIND"     => { "spa" => 1, "spd" => 1 },
      "BULKUP"       => { "atk" => 1, "def" => 1 },
      "COIL"         => { "atk" => 1, "def" => 1 },
      "HONECLAWS"    => { "atk" => 1 },
      "WORKUP"       => { "atk" => 1, "spa" => 1 },
      "GROWTH"       => { "atk" => 1, "spa" => 1 },
      "CURSE"        => { "atk" => 1, "def" => 1, "speed" => -1 },
      "SHELLSMASH"   => { "atk" => 2, "spa" => 2, "speed" => 2,
                          "def" => -1, "spd" => -1 },
      "GEOMANCY"     => { "spa" => 2, "spd" => 2, "speed" => 2 },
      "BELLYDRUM"    => { "atk" => 6 },
      "AGILITY"      => { "speed" => 2 },
      "ROCKPOLISH"   => { "speed" => 2 },
      "AUTOTOMIZE"   => { "speed" => 2 },
      "IRONDEFENSE"  => { "def" => 2 },
      "ACIDARMOR"    => { "def" => 2 },
      "BARRIER"      => { "def" => 2 },
      "AMNESIA"      => { "spd" => 2 },
      "COSMICPOWER"  => { "def" => 1, "spd" => 1 },
      "STOCKPILE"    => { "def" => 1, "spd" => 1 },
      "DEFENDORDER"  => { "def" => 1, "spd" => 1 }
    }

    # The engine's own stage table as ratios (085_PokeBattle_AI.rb:2932 holds the same
    # numbers as numerator/denominator pairs). Index is the absolute stage; a drop is
    # the reciprocal, which is what the engine's pair table spells out row by row.
    STAGE_MULT = [1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]

    add(%w[SOLARBEAM SOLARBLADE], ["charge_solar"])
    add(%w[PROTECT DETECT KINGSSHIELD SPIKYSHIELD BANEFULBUNKER
           OBSTRUCT SILKTRAP BURNINGBULWARK], ["protect"])
    add(%w[SUBSTITUTE], ["substitute"])

    # Status kinds let adapters derive immunity facts (burn vs Fire-types, poison vs
    # Steel, powder vs Grass, paralysis vs Electric). "typed_status" marks moves whose
    # own type immunity blocks them (Thunder Wave vs Ground) — Glare deliberately lacks
    # it because modern engines let it hit Ghost-types.
    add(%w[THUNDERWAVE], ["status", "paralyze", "typed_status"])
    add(%w[GLARE], ["status", "paralyze"])
    add(%w[STUNSPORE], ["status", "paralyze", "powder"])
    add(%w[WILLOWISP], ["status", "burn"])
    add(%w[TOXIC], ["status", "poison"])
    add(%w[POISONPOWDER], ["status", "poison", "powder"])
    add(%w[SPORE SLEEPPOWDER], ["status", "sleep", "powder"])
    add(%w[HYPNOSIS DARKVOID], ["status", "sleep"])
    # Yawn puts the target to sleep NEXT turn by writing PBEffects::Yawn, so it fails
    # against an already-drowsy target while pbCanSleep? still says yes. It carries its
    # own tag purely so the adapter's status_blocked? can find it without a move-name
    # lookup -- the same shape as "drain" on LEECHSEED below.
    add(%w[YAWN], ["status", "sleep", "drowsy"])
    add(%w[CONFUSERAY SWAGGER FLATTER], ["status", "confuse"])
    add(%w[LEECHSEED], ["status", "drain"])
    add(%w[TAUNT ENCORE TORMENT DISABLE HEALBLOCK PSYCHICNOISE], ["disrupt"])
    add(%w[HAZE CLEARSMOG], ["reset_stages"])

    add(%w[STEALTHROCK SPIKES TOXICSPIKES STICKYWEB], ["hazard"])
    add(%w[RAPIDSPIN DEFOG MORTALSPIN TIDYUP], ["hazard_remove"])
    add(%w[REFLECT LIGHTSCREEN AURORAVEIL SAFEGUARD MIST], ["screen"])

    add(%w[UTURN VOLTSWITCH FLIPTURN PARTINGSHOT TELEPORT], ["pivot"])
    add(%w[ROAR WHIRLWIND DRAGONTAIL CIRCLETHROW], ["force_switch"])
    add(%w[BATONPASS], ["baton_pass"])
    add(%w[TRICK SWITCHEROO KNOCKOFF CORROSIVEGAS], ["item_control"])
    # Knock Off alone actually REMOVES the item; Trick and Switcheroo swap it, which
    # is a different trade the core does not price. Reborn's knockcode (:8072) is a
    # short whitelist and nothing else, so the tag exists to reach that one rule.
    add(%w[KNOCKOFF], ["item_removal"])

    add(%w[FOLLOWME RAGEPOWDER SPOTLIGHT], ["redirect"])
    # 0.5.0 tables. "speed_control" is anything that changes who moves first;
    # "field_speed" narrows that to the two whole-turn investments, which are the only
    # ones with a "already active, do not repeat" case. "first_turn_only" and
    # "delayed_damage" each need one engine fact (turncount, effect_active) that the
    # adapter now exports. "partner_heal" is a move that does nothing at all in
    # singles.
    add(%w[TRICKROOM TAILWIND STICKYWEB ICYWIND ELECTROWEB ROCKTOMB
           BULLDOZE ICESPINNER], ["speed_control"])
    add(%w[TRICKROOM TAILWIND], ["speed_control", "field_speed"])
    add(%w[FAKEOUT FIRSTIMPRESSION], ["first_turn_only"])
    add(%w[FUTURESIGHT DOOMDESIRE], ["delayed_damage"])
    add(%w[HEALPULSE POLLENPUFF LIFEDEW FLORALHEALING], ["partner_heal"])
    add(%w[HELPINGHAND COACHING DECORATE], ["partner_support"])
    add(%w[WIDEGUARD QUICKGUARD MATBLOCK CRAFTYSHIELD], ["team_protect"])

    add(%w[EARTHQUAKE SURF DISCHARGE SLUDGEWAVE BOOMBURST EXPLOSION
           SELFDESTRUCT LAVAPLUME PETALBLIZZARD BULLDOZE], ["spread", "friendly_fire"])
    add(%w[ROCKSLIDE HEATWAVE DAZZLINGGLEAM MUDDYWATER BLIZZARD
           ICYWIND RAZORLEAF AIRSLASH SNARL TWISTER], ["spread"])
    add(%w[FAKEOUT EXTREMESPEED AQUAJET BULLETPUNCH MACHPUNCH
           ICESHARD SHADOWSNEAK SUCKERPUNCH VACUUMWAVE], ["priority"])

    # Moves that pay for their damage. "self_drop" wrecks the user's own offence for
    # the rest of the turn cycle; "self_ko" ends the user outright. Reborn charges
    # both (selfstatdrop :6118, deathcode :7779) and Portable over-used every move on
    # these two lists relative to it.
    add(%w[DRACOMETEOR OVERHEAT LEAFSTORM PSYCHOBOOST FLEURCANNON
           SUPERPOWER CLOSECOMBAT VCREATE HAMMERARM DRAGONASCENT], ["self_drop"])
    add(%w[EXPLOSION SELFDESTRUCT FINALGAMBIT MEMENTO HEALINGWISH
           LUNARDANCE], ["self_ko"])

    # Adapters that cannot compute Essentials function codes fall back to bare kind
    # tags ("secondary:burn"), so the core can still find the kind without a chance.
    # The Reborn adapter exports effect_kind/effect_chance from the code map instead
    # and never needs these; they exist so the same core runs on a thinner adapter.
    # A stage as a damage ratio. Negative stages are the reciprocal, which is what
    # the engine's own pair table spells out row by row; clamped at +-6 as the engine
    # clamps the stage itself.
    def self.stage_multiplier(stage)
      value = stage.to_i
      value = 6 if value > 6
      value = -6 if value < -6
      return STAGE_MULT[value] if value >= 0
      1.0 / STAGE_MULT[-value]
    end

    # nil for a move with no row, which the setup consumer reads as "price it the old
    # way" rather than as "it raises nothing".
    def self.setup_stages(move_id)
      SETUP_STAGES[move_id.to_s.upcase]
    end

    def self.kind_of(tags, prefix)
      head = prefix.to_s + ":"
      (tags || []).each do |tag|
        value = tag.to_s
        return value[head.length, value.length] if value.index(head) == 0
      end
      nil
    end

    def self.describe(move_id, supplied_tags)
      tags = []
      (TABLE[move_id.to_s.upcase] || []).each { |tag| tags << tag }
      (supplied_tags || []).each do |tag|
        value = tag.to_s
        tags << value if !tags.include?(value)
      end
      tags
    end

    def self.tagged?(move_id, supplied_tags, tag)
      describe(move_id, supplied_tags).include?(tag)
    end
  end
end
