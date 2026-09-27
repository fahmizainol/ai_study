#!/usr/bin/env python3
"""A one-shot Scripts.rxdata that makes Realidea's mkxp-z player compile the PBS.

Realidea ships as an mkxp-z build, and its Compiler section runs only `if $DEBUG &&
!$MKXP`: the shipped player NEVER recompiles PBS/*.txt into Data/*.dat, and the stock
RGSS player it also ships crashes on the machine the game is played on (RNB-STUDY.md
§10). So after any PBS change (tools/learnset_merge.py) the compile has to be forced.

This writes a copy of the current bundle whose Compiler section compiles unconditionally
at load, with the Win32-only progress call replaced by a no-op (under mkxp it would raise,
and the compiler's rescue then DELETES every Data/*.dat). Use it like this, from the game
folder, with Data/portable_ai.txt set aside so the Foul Play gate does not refuse the boot:

    python3 tools/compile_pbs_bundle.py [--game DIR]       -> generated/compile_pbs/Scripts.rxdata
    copy Data/Scripts.rxdata aside; copy the staged file over it; start Game.exe once
    (it compiles, then shows the title); quit; put the real bundle back.

Back up Data/*.dat first. The result is the 21 data files plus Constants.rxdata and
messages.dat, rewritten; commit those with the PBS change so nobody else has to do this.
Verified on the Deck under Proton on 2026-09-27/28 (memory: realidea-under-proton).
"""
import os
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pack_rxdata as PR  # noqa: E402

GAME = os.path.abspath(os.path.join(HERE, "..", "..", "Realidea V4.1"))
OUT = os.path.join(HERE, "..", "generated", "compile_pbs")
EDITS = [
    ("  if $DEBUG && !$MKXP\n", "  if true\n"),
    ("    mustcompile=mustcompile || (latesttexttime>=latestdatatime)\n", "    mustcompile=true\n"),
    ("    pbCompileAllData(mustcompile){|msg| Win32API.SetWindowText(msg) }\n",
     "    pbCompileAllData(mustcompile){|msg| }\n"),
]


def main(argv):
    game = argv[argv.index("--game") + 1] if "--game" in argv else GAME
    bundle = os.path.join(game, "Data", "Scripts.rxdata")
    raw, count, spans = PR.scan(bundle)
    names = [n.decode() if isinstance(n, bytes) else n for n in PR.section_names(bundle)]
    idx = names.index("Compiler")
    blob = raw[spans[idx][0]:spans[idx][1]]
    src = zlib.decompress(blob[blob.find(b"x\x9c"):]).decode("utf-8")
    for old, new in EDITS:
        if src.count(old) != 1:
            sys.exit(f"Compiler section: anchor found {src.count(old)} times, expected 1:\n{old}")
        src = src.replace(old, new)
    out = PR.build(raw, spans, replace={idx: PR.make_elem("Compiler", src.encode("utf-8"))})
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "Scripts.rxdata")
    with open(path, "wb") as fh:
        fh.write(out)
    print(f"staged -> {path} ({len(out)} bytes); this bundle is for ONE compile run, never to ship")


if __name__ == "__main__":
    main(sys.argv)
