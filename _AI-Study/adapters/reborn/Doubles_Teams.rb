# Focused doubles fixture derived from the public Pokemon Showdown Gen 8 Doubles OU
# set data. It is deliberately separate from the historical set_a..set_g singles
# fixtures so adding doubles coverage cannot change an existing benchmark frame.
module PortableAIRebornTeams
  SETS["doubles_a"] = {
    "offense" => [
      ["POLITOED", %w[SCALD HELPINGHAND ICYWIND PROTECT],
       { "item" => "SITRUSBERRY", "ability" => 2 }],
      ["KINGDRA", %w[MUDDYWATER HURRICANE DRACOMETEOR PROTECT],
       { "item" => "LIFEORB", "ability" => 0 }],
      ["LUDICOLO", %w[FAKEOUT SCALD GIGADRAIN ICEBEAM],
       { "item" => "ASSAULTVEST", "ability" => 0 }],
      ["ZAPDOS", %w[THUNDERBOLT HEATWAVE TAILWIND PROTECT],
       { "item" => "LEFTOVERS", "ability" => 0 }],
      ["SCIZOR", %w[BULLETPUNCH XSCISSOR SWORDSDANCE PROTECT],
       { "item" => "LIFEORB", "ability" => 0 }],
      ["GASTRODON", %w[SCALD EARTHPOWER RECOVER PROTECT],
       { "item" => "LEFTOVERS", "ability" => 1 }]
    ],
    "balance" => [
      ["TOGEKISS", %w[AIRSLASH DAZZLINGGLEAM FOLLOWME PROTECT],
       { "item" => "SITRUSBERRY", "ability" => 1 }],
      ["GARCHOMP", %w[EARTHQUAKE DRAGONCLAW SWORDSDANCE PROTECT],
       { "item" => "LIFEORB", "ability" => 0 }],
      ["VOLCARONA", %w[HEATWAVE BUGBUZZ RAGEPOWDER QUIVERDANCE],
       { "item" => "SITRUSBERRY", "ability" => 0 }],
      ["METAGROSS", %w[METEORMASH EARTHQUAKE ZENHEADBUTT PROTECT],
       { "item" => "WEAKNESSPOLICY", "ability" => 0 }],
      ["SYLVEON", %w[HYPERVOICE MOONBLAST HELPINGHAND PROTECT],
       { "item" => "LEFTOVERS", "ability" => 2 }],
      ["HITMONTOP", %w[FAKEOUT CLOSECOMBAT WIDEGUARD PROTECT],
       { "item" => "SITRUSBERRY", "ability" => 1 }]
    ],
    "speed" => [
      ["WHIMSICOTT", %w[TAILWIND MOONBLAST HELPINGHAND PROTECT],
       { "item" => "FOCUSSASH", "ability" => 0 }],
      ["PERSIAN", %w[FAKEOUT KNOCKOFF TAUNT UTURN],
       { "item" => "SITRUSBERRY", "ability" => 0 }],
      ["EXCADRILL", %w[EARTHQUAKE IRONHEAD ROCKSLIDE PROTECT],
       { "item" => "LIFEORB", "ability" => 1 }],
      ["TYRANITAR", %w[ROCKSLIDE CRUNCH EARTHQUAKE PROTECT],
       { "item" => "WEAKNESSPOLICY", "ability" => 0 }],
      ["CROBAT", %w[TAILWIND TAUNT BRAVEBIRD SUPERFANG],
       { "item" => "SITRUSBERRY", "ability" => 0 }],
      ["ROTOM", %w[THUNDERBOLT SHADOWBALL VOLTSWITCH WILLOWISP],
       { "item" => "LEFTOVERS", "ability" => 0 }]
    ],
    "bulky" => [
      ["REUNICLUS", %w[PSYCHIC FOCUSBLAST RECOVER TRICKROOM],
       { "item" => "LEFTOVERS", "ability" => 2 }],
      ["TORKOAL", %w[ERUPTION HEATWAVE EARTHPOWER PROTECT],
       { "item" => "CHARCOAL", "ability" => 1 }],
      ["AMOONGUSS", %w[SPORE RAGEPOWDER POLLENPUFF PROTECT],
       { "item" => "SITRUSBERRY", "ability" => 2 }],
      ["PORYGON2", %w[TRIATTACK ICEBEAM RECOVER TRICKROOM],
       { "item" => "EVIOLITE", "ability" => 1 }],
      ["RHYPERIOR", %w[ROCKSLIDE EARTHQUAKE MEGAHORN PROTECT],
       { "item" => "WEAKNESSPOLICY", "ability" => 0 }],
      ["HARIYAMA", %w[FAKEOUT CLOSECOMBAT KNOCKOFF WIDEGUARD],
       { "item" => "ASSAULTVEST", "ability" => 0 }]
    ]
  }
end
