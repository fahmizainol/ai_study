#!/usr/bin/env python3
"""Instruction-level identity check between two poke-engine builds.

Answers "did this refactor change the singles board?" deterministically, without a
game: for every state in a corpus it compares both builds' root option lists and the
instruction set emitted for every legal joint pair. `generate-instructions` has no RNG,
so any difference is a real behavioural change.

Used on 2026-09-12 to check poke-engine PR #10 (the doubles rewrite) against its own
base 60e1cf8a2: 102/102 option lists and 4546/4546 instruction sets identical. See the
"PR #10" section of SEARCH-BOARDS.md.

  # build the two binaries you want to compare, e.g. in one clone:
  git checkout <base>  && cargo build --release --features gen9 && cp target/release/poke-engine ../pe-base
  git checkout <other> && cargo build --release --features gen9 && cp target/release/poke-engine ../pe-fork-singles
  python3 tools/pe_identity.py [scratch-dir]

Expects <scratch-dir>/{pe-base,pe-fork-singles} and the state corpus at
<scratch-dir>/pe-doubles/data/gen9randombattle.txt. A non-zero mismatch count is the
whole signal; the first four differing cases are printed in full.
"""
import subprocess, sys, pathlib
SC = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
BASE, FORK = SC/"pe-base", SC/"pe-fork-singles"
states = [l.strip() for l in open(SC/"pe-doubles/data/gen9randombattle.txt") if l.strip()]

def run(binary, args):
    r = subprocess.run([str(binary)] + args, capture_output=True, text=True, timeout=120)
    return r.stdout.strip(), r.stderr.strip(), r.returncode

def options(binary, state):
    out, _, _ = run(binary, ["monte-carlo-tree-search", "--state", state, "-i", "1"])
    side = {}
    for line in out.splitlines():
        if line.startswith("side one:") or line.startswith("side two:"):
            k = line.split(":")[0].split()[1]
            side[k] = [p.split(",")[0] for p in line.split(":", 1)[1].strip().split("|") if p]
    return side.get("one", []), side.get("two", [])

opt_mismatch, instr_mismatch, pairs, examples = 0, 0, 0, []
for i, st in enumerate(states):
    b1, b2 = options(BASE, st)
    f1, f2 = options(FORK, st)
    if (b1, b2) != (f1, f2):
        opt_mismatch += 1
        if len(examples) < 4:
            examples.append(f"state {i} OPTIONS differ\n  base: {b1} / {b2}\n  fork: {f1} / {f2}")
        continue
    for o in b1:
        for t in b2:
            a = ["generate-instructions", "--state", st, "-o", o, "-t", t]
            ob, eb, cb = run(BASE, a)
            of, ef, cf = run(FORK, a)
            pairs += 1
            if (ob, cb) != (of, cf):
                instr_mismatch += 1
                if len(examples) < 4:
                    examples.append(f"state {i} pair {o} vs {t} INSTRUCTIONS differ\n"
                                    f"--- base (rc={cb})\n{ob[:1200]}\n--- fork (rc={cf})\n{of[:1200]}")
    if i % 20 == 0:
        print(f"  ...{i+1}/{len(states)} states, {pairs} pairs, {opt_mismatch} opt / {instr_mismatch} instr mismatches", flush=True)

print(f"\nstates            : {len(states)}")
print(f"option lists      : {len(states)-opt_mismatch} identical, {opt_mismatch} differ")
print(f"move pairs        : {pairs}")
print(f"instruction sets  : {pairs-instr_mismatch} identical, {instr_mismatch} differ")
for e in examples:
    print("\n" + e)
