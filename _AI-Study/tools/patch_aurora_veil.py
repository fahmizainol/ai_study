#!/usr/bin/env python3
"""Finish Aurora Veil in Realidea's battle engine, as a staged Scripts.rxdata.

Realidea ships the move's SETTER (PokeBattle_Move_CF6: needs hail, 5 turns, 8 with Light
Clay) and nothing else: no PBEffects::AuroraVeil constant, so using the move raises an
uninitialised-constant error; no side-field init; no damage hook; no countdown; Defog,
Brick Break and Shadow Shed do not clear it. This mirrors every place the engine handles
Reflect (RNB-STUDY.md §10 lists them) and writes the result to a STAGED copy:

    python3 tools/patch_aurora_veil.py [--game DIR]   -> generated/aurora_veil/Scripts.rxdata

The game's own bundle is never written here. Installing is a deliberate copy of the staged
file over Realidea V4.1/Data/Scripts.rxdata (keep the original beside it), followed by the
same debug-mode start any script change needs. Every anchor must match exactly once, or
the tool refuses -- a partial patch is worse than none.

Semantics (gen 7): halves damage of both categories, 2/3 in doubles, ignored by critical
hits and Infiltrator like the screens, does not stack with Reflect / Light Screen on the
category they already cover, counts down at the end of each round with the screens, and is
removed by Defog, Brick Break / Psychic Fangs and Shadow Shed.
"""
import os
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pack_rxdata as PR  # noqa: E402

GAME = os.path.abspath(os.path.join(HERE, "..", "..", "Realidea V4.1"))
OUT = os.path.join(HERE, "..", "generated", "aurora_veil")

# (section, anchor, replacement, expected count)
EDITS = [
    ("PBEffects",
     "    WideGuard          = 20\n",
     "    WideGuard          = 20\n    AuroraVeil         = 21\n", 1),
    ("PokeBattle_ActiveSideField",
     "      @effects[PBEffects::Reflect]            = 0\n",
     "      @effects[PBEffects::Reflect]            = 0\n"
     "      @effects[PBEffects::AuroraVeil]         = 0\n", 1),
    ("PokeBattle_Move",
     "      # Light Screen\n"
     "      if opponent.pbOwnSide.effects[PBEffects::LightScreen]>0 && pbIsSpecial?(type)\n"
     "        if @battle.doublebattle\n"
     "          finaldamagemult=(finaldamagemult*0.66).round\n"
     "        else\n"
     "          finaldamagemult=(finaldamagemult*0.5).round\n"
     "        end\n"
     "      end\n",
     "      # Light Screen\n"
     "      if opponent.pbOwnSide.effects[PBEffects::LightScreen]>0 && pbIsSpecial?(type)\n"
     "        if @battle.doublebattle\n"
     "          finaldamagemult=(finaldamagemult*0.66).round\n"
     "        else\n"
     "          finaldamagemult=(finaldamagemult*0.5).round\n"
     "        end\n"
     "      end\n"
     "      # Aurora Veil: both categories, but not on top of the screen already covering one\n"
     "      if opponent.pbOwnSide.effects[PBEffects::AuroraVeil]>0 &&\n"
     "         !(opponent.pbOwnSide.effects[PBEffects::Reflect]>0 && pbIsPhysical?(type)) &&\n"
     "         !(opponent.pbOwnSide.effects[PBEffects::LightScreen]>0 && pbIsSpecial?(type))\n"
     "        if @battle.doublebattle\n"
     "          finaldamagemult=(finaldamagemult*0.66).round\n"
     "        else\n"
     "          finaldamagemult=(finaldamagemult*0.5).round\n"
     "        end\n"
     "      end\n", 1),
    # Defog, both the move and its additional-effect form, own side and (new mechanics) both
    ("PokeBattle_MoveEffects",
     "opponent.pbOwnSide.effects[PBEffects::Reflect]     = 0\n",
     "opponent.pbOwnSide.effects[PBEffects::Reflect]     = 0\n"
     "    opponent.pbOwnSide.effects[PBEffects::AuroraVeil]  = 0\n", 2),
    ("PokeBattle_MoveEffects",
     "opponent.pbOpposingSide.effects[PBEffects::Reflect]     = 0\n",
     "opponent.pbOpposingSide.effects[PBEffects::Reflect]     = 0\n"
     "      opponent.pbOpposingSide.effects[PBEffects::AuroraVeil]  = 0\n", 2),
    # Brick Break / Psychic Fangs
    ("PokeBattle_MoveEffects",
     "    ret=super(attacker,opponent,hitnum,alltargets,showanimation)\n"
     "    if attacker.pbOpposingSide.effects[PBEffects::Reflect]>0\n"
     "      attacker.pbOpposingSide.effects[PBEffects::Reflect]=0\n",
     "    ret=super(attacker,opponent,hitnum,alltargets,showanimation)\n"
     "    if attacker.pbOpposingSide.effects[PBEffects::AuroraVeil]>0\n"
     "      attacker.pbOpposingSide.effects[PBEffects::AuroraVeil]=0\n"
     "      if !@battle.pbIsOpposing?(attacker.index)\n"
     "        @battle.pbDisplay(_INTL(\"¡Velo Aurora del equipo enemigo no funciona!\"))\n"
     "      else\n"
     "        @battle.pbDisplayPaused(_INTL(\"¡Velo Aurora no funciona en tu equipo!\"))\n"
     "      end\n"
     "    end\n"
     "    if attacker.pbOpposingSide.effects[PBEffects::Reflect]>0\n"
     "      attacker.pbOpposingSide.effects[PBEffects::Reflect]=0\n", 1),
    ("PokeBattle_MoveEffects",
     "    if attacker.pbOpposingSide.effects[PBEffects::Reflect]>0 ||\n"
     "       attacker.pbOpposingSide.effects[PBEffects::LightScreen]>0\n"
     "      return super(id,attacker,opponent,1,alltargets,showanimation) # Wall-breaking anim\n",
     "    if attacker.pbOpposingSide.effects[PBEffects::Reflect]>0 ||\n"
     "       attacker.pbOpposingSide.effects[PBEffects::LightScreen]>0 ||\n"
     "       attacker.pbOpposingSide.effects[PBEffects::AuroraVeil]>0\n"
     "      return super(id,attacker,opponent,1,alltargets,showanimation) # Wall-breaking anim\n", 1),
    # end-of-round countdown, beside the screens
    ("PokeBattle_Battle",
     "    # Pantalla Luz  /  Light Screen\n",
     "    # Velo Aurora  /  Aurora Veil\n"
     "    for i in 0...2\n"
     "      if sides[i].effects[PBEffects::AuroraVeil]>0\n"
     "        sides[i].effects[PBEffects::AuroraVeil]-=1\n"
     "        if sides[i].effects[PBEffects::AuroraVeil]==0\n"
     "          pbDisplay(_INTL(\"¡Los efectos de Velo Aurora de tu equipo se disiparon!\")) if i==0\n"
     "          pbDisplay(_INTL(\"¡Los efectos de Velo Aurora del equipo enemigo se disiparon!\")) if i==1\n"
     "          PBDebug.log(\"[Fin de efecto] Velo Aurora del lado del jugador terminó\") if i==0\n"
     "          PBDebug.log(\"[Fin de efecto] Velo Aurora del lado del oponente terminó\") if i==1\n"
     "        end\n"
     "      end\n"
     "    end\n"
     "    # Pantalla Luz  /  Light Screen\n", 1),
    # the stock AI: screen-breaking is worth more, and rough damage respects the veil
    ("PokeBattle_AI",
     "      score+=30 if opponent.pbOwnSide.effects[PBEffects::Reflect]>0 ||\n"
     "                   opponent.pbOwnSide.effects[PBEffects::LightScreen]>0 ||\n",
     "      score+=30 if opponent.pbOwnSide.effects[PBEffects::Reflect]>0 ||\n"
     "                   opponent.pbOwnSide.effects[PBEffects::LightScreen]>0 ||\n"
     "                   opponent.pbOwnSide.effects[PBEffects::AuroraVeil]>0 ||\n", 1),
    ("PokeBattle_AI",
     "    # Light Screen\n"
     "    if skill>=PBTrainerAI.highSkill\n",
     "    # Aurora Veil\n"
     "    if skill>=PBTrainerAI.highSkill\n"
     "      if opponent.pbOwnSide.effects[PBEffects::AuroraVeil]>0 &&\n"
     "         !(opponent.pbOwnSide.effects[PBEffects::Reflect]>0 && move.pbIsPhysical?(type)) &&\n"
     "         !(opponent.pbOwnSide.effects[PBEffects::LightScreen]>0 && move.pbIsSpecial?(type))\n"
     "        if !opponent.pbPartner.isFainted?\n"
     "          damage=(damage*0.66).round\n"
     "        else\n"
     "          damage=(damage*0.5).round\n"
     "        end\n"
     "      end\n"
     "    end\n"
     "    # Light Screen\n"
     "    if skill>=PBTrainerAI.highSkill\n", 1),
    # Shadow Shed clears every screen
    ("Pokemon_ShadowPokemon",
     "       @battle.sides[1].effects[PBEffects::Safeguard]>0\n"
     "      pbShowAnimation(@id,attacker,nil,hitnum,alltargets,showanimation)\n"
     "      @battle.sides[0].effects[PBEffects::Reflect]=0\n",
     "       @battle.sides[1].effects[PBEffects::Safeguard]>0 ||\n"
     "       @battle.sides[0].effects[PBEffects::AuroraVeil]>0 ||\n"
     "       @battle.sides[1].effects[PBEffects::AuroraVeil]>0\n"
     "      pbShowAnimation(@id,attacker,nil,hitnum,alltargets,showanimation)\n"
     "      @battle.sides[0].effects[PBEffects::AuroraVeil]=0\n"
     "      @battle.sides[1].effects[PBEffects::AuroraVeil]=0\n"
     "      @battle.sides[0].effects[PBEffects::Reflect]=0\n", 1),
    # the study's own probe reads it like the screens
    ("AI_Probe",
     "    \"reflect\"     => [PBEffects::Reflect,     :int],\n",
     "    \"reflect\"     => [PBEffects::Reflect,     :int],\n"
     "    \"auroraveil\"  => [PBEffects::AuroraVeil,  :int],\n", 1),
]


def sections(bundle):
    raw, count, spans = PR.scan(bundle)
    names = [n.decode() if isinstance(n, bytes) else n for n in PR.section_names(bundle)]
    src = {}
    for i, ((a, b), n) in enumerate(zip(spans, names)):
        blob = raw[a:b]
        j = blob.find(b"x\x9c")
        if j < 0:
            continue
        try:
            src[n] = (i, zlib.decompress(blob[j:]).decode("utf-8"))
        except Exception:
            pass
    return raw, spans, names, src


def main(argv):
    game = argv[argv.index("--game") + 1] if "--game" in argv else GAME
    bundle = os.path.join(game, "Data", "Scripts.rxdata")
    raw, spans, names, src = sections(bundle)
    if "PBEffects" in src and "AuroraVeil" in src["PBEffects"][1]:
        sys.exit("this bundle already defines PBEffects::AuroraVeil -- nothing to do")
    changed = {}
    for sec, anchor, new, n in EDITS:
        idx, text = changed.get(sec) or src[sec]
        got = text.count(anchor)
        if got != n:
            sys.exit(f"{sec}: anchor found {got} times, expected {n}:\n{anchor}")
        changed[sec] = (idx, text.replace(anchor, new))
    replace = {idx: PR.make_elem(sec, text.encode("utf-8")) for sec, (idx, text) in changed.items()}
    out = PR.build(raw, spans, replace=replace)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "Scripts.rxdata")
    with open(path, "wb") as fh:
        fh.write(out)
    # prove the result reads back with the same sections and the edits in place
    raw2, spans2, names2, src2 = sections(path)
    assert names2 == names, "section list changed"
    for sec, (idx, text) in changed.items():
        assert src2[sec][1] == text, f"{sec} did not round-trip"
    added = sum(text.count("\n") - src[sec][1].count("\n") for sec, (idx, text) in changed.items())
    print(f"patched {len(changed)} sections ({', '.join(sorted(changed))}), +{added} lines")
    print(f"staged -> {path}  ({len(out)} bytes; original {len(raw)})")
    print(f"install: copy it over {bundle} (keep a copy of the original), then start the game in debug mode once")


if __name__ == "__main__":
    main(sys.argv)
