#!/usr/bin/env python3
"""Install the study's harness + portable AI into a Reborn Yang checkout.

The game tree is not in git (see README.md), so a fresh clone has the study's code
but none of it is in the game. This puts it there. Idempotent: run it after every
rebuild, or twice in a row — the host edits are applied at most once.

What it installs:
  Scripts/AI_Harness.rb      <- adapters/reborn/AI_Harness.rb   (the batch runner)
  Scripts/Portable_AI.rb     <- generated/Portable_AI_Reborn.rb (built if missing/stale)
  Data/!script_order.csv     two entries inserted before Main
  Scripts/Main.rb            one opt-in hook wrapped around the main loop

Both host edits are inert until Data/ai_harness.txt exists, and both are reversible:
originals are copied to backups/ the first time each is touched.

Usage:
  python3 tools/install_reborn.py                       # ../Reborn Yang/Reborn Yang
  python3 tools/install_reborn.py --game "/path/to/Reborn Yang" [--no-build] [--check]
"""
import argparse, filecmp, shutil, subprocess, sys
from pathlib import Path

STUDY = Path(__file__).resolve().parent.parent
MARK = "_AI-Study"

# The main loop Main.rb ends with, and the hook that wraps it. Matched exactly: if the
# host file does not contain this block verbatim we refuse rather than guess.
MAIN_LOOP = """loop do
  retval=mainFunction
  if retval==0 # failed
    loop do
      Graphics.update
    end
  elsif retval==1 # ended successfully
    break
  end
end"""

MAIN_HOOK_OPEN = """# _AI-Study: opt-in AI batch runner. No effect unless Data/ai_harness.txt exists.
if defined?(AIHarness) && AIHarness.requested?
  begin
    AIHarness.run
  rescue Exception => e
    msg = "AIHarness FATAL: #{e.class}: #{e.message}\\n" + e.backtrace.to_a[0, 12].join("\\n")
    $stdout.print(msg, "\\n") rescue nil
    $stdout.flush rescue nil
    (File.open("Data/ai_harness_error.txt", "wb") { |f| f.write(msg) }) rescue nil
  end
else

"""


def backup(path, name):
    dest = STUDY / "backups" / name
    if not dest.exists():
        shutil.copy2(path, dest)
        print(f"    backed up original -> backups/{name}")


def copy_script(src, dest, label):
    if dest.exists() and filecmp.cmp(src, dest, shallow=False):
        print(f"  = {label}: already current")
        return False
    shutil.copy2(src, dest)
    print(f"  + {label}: installed ({src.stat().st_size:,} bytes)")
    return True


def patch_script_order(csv, check):
    text = csv.read_text(encoding="utf-8")
    lines = text.splitlines()
    want = [n for n in ("AI_Harness", "Portable_AI") if n not in lines]
    if not want:
        print("  = !script_order.csv: AI_Harness and Portable_AI already listed")
        return False
    if check:
        print(f"  ! !script_order.csv: MISSING {', '.join(want)}")
        return True
    if "Main" not in lines:
        sys.exit("!script_order.csv has no 'Main' entry — is this a Reborn checkout?")
    backup(csv, "reborn_script_order.csv.orig")
    at = lines.index("Main")
    for i, name in enumerate(want):
        lines.insert(at + i, name)
    csv.write_text("\n".join(lines) + ("\n" if text.endswith("\n") else ""), encoding="utf-8")
    print(f"  + !script_order.csv: inserted {', '.join(want)} before Main")
    return True


def patch_main(main, check):
    text = main.read_text(encoding="utf-8")
    if MARK in text:
        print("  = Main.rb: harness hook already present")
        return False
    if check:
        print("  ! Main.rb: harness hook MISSING")
        return True
    if text.count(MAIN_LOOP) != 1:
        sys.exit(
            "Main.rb does not contain the expected main loop exactly once, so the hook\n"
            "cannot be placed safely. Apply it by hand: wrap the `loop do retval=mainFunction`\n"
            "block in the `if defined?(AIHarness) && AIHarness.requested?` guard shown in\n"
            "tools/install_reborn.py, and close it with a matching `end`."
        )
    backup(main, "reborn_Main.rb.orig")
    text = text.replace(MAIN_LOOP, MAIN_HOOK_OPEN + MAIN_LOOP + "\n\nend")
    main.write_text(text, encoding="utf-8")
    print("  + Main.rb: wrapped the main loop in the opt-in harness hook")
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game", default=str(STUDY.parent / "Reborn Yang" / "Reborn Yang"),
                    help="the directory holding Scripts/ and Data/")
    ap.add_argument("--no-build", action="store_true", help="use generated/ as-is")
    ap.add_argument("--check", action="store_true", help="report only, change nothing")
    args = ap.parse_args()

    game = Path(args.game)
    if not (game / "Scripts" / "Main.rb").exists() or not (game / "Data").is_dir():
        sys.exit(f"not a Reborn Yang checkout (no Scripts/Main.rb): {game}")
    print(f"{'Checking' if args.check else 'Installing into'} {game}")

    bundle = STUDY / "generated" / "Portable_AI_Reborn.rb"
    if not args.check and not args.no_build:
        subprocess.run([sys.executable, str(STUDY / "tools" / "build_portable_ai.py"),
                        "--target", "reborn"], check=True, cwd=STUDY)
    if not bundle.exists():
        sys.exit(f"missing {bundle} — run tools/build_portable_ai.py --target reborn")

    changed = False
    for src, dest, label in (
        (STUDY / "adapters" / "reborn" / "AI_Harness.rb", game / "Scripts" / "AI_Harness.rb", "AI_Harness.rb"),
        (bundle, game / "Scripts" / "Portable_AI.rb", "Portable_AI.rb"),
    ):
        if args.check:
            state = "current" if dest.exists() and filecmp.cmp(src, dest, shallow=False) else \
                    ("STALE" if dest.exists() else "MISSING")
            print(f"  {'=' if state == 'current' else '!'} {label}: {state}")
            changed |= state != "current"
        else:
            changed |= copy_script(src, dest, label)

    changed |= patch_script_order(game / "Data" / "!script_order.csv", args.check)
    changed |= patch_main(game / "Scripts" / "Main.rb", args.check)

    if args.check:
        print("\nnot installed / out of date" if changed else "\nfully installed")
        return 1 if changed else 0
    print("\nInstalled. The harness and the portable AI are both OFF until you create")
    print("  Data/ai_harness.txt   (harness config: mode=probe or mode=gauntlet)")
    print("  Data/portable_ai.txt  (marker: portable AI drives the trainer side)")
    print("Delete both and the game boots exactly as before.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
