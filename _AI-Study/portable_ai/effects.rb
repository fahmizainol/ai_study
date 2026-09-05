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
    add(%w[HYPNOSIS DARKVOID YAWN], ["status", "sleep"])
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
