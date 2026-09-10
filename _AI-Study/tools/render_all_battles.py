#!/usr/bin/env python3
"""Render every traced Reborn gauntlet record into one readable text log."""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


def safe_name(value):
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", str(value)).strip("_")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("results", type=Path)
    parser.add_argument("out_dir", type=Path)
    parser.add_argument("--arm", default="normal_portable")
    args = parser.parse_args()

    renderer = Path(__file__).with_name("render_battle.py")
    args.out_dir.mkdir(parents=True, exist_ok=True)
    records = []
    with args.results.open(encoding="utf-8") as source:
        for line in source:
            record = json.loads(line)
            if record.get("arm", "normal_portable") != args.arm:
                continue
            if not record.get("commands"):
                continue
            records.append(record)

    index = []
    all_battles = []
    for number, record in enumerate(records, 1):
        filename = "%03d_%s_seed_%s.txt" % (
            number, safe_name(record["id"]), record["seed"])
        target = args.out_dir / filename
        command = [sys.executable, str(renderer), str(args.results), record["id"],
                   str(record["seed"]), "--arm=" + args.arm]
        completed = subprocess.run(command, check=True, capture_output=True, text=True)
        rendered = "\n".join(line.rstrip() for line in completed.stdout.splitlines()) + "\n"
        target.write_text(rendered, encoding="utf-8")
        all_battles.append(rendered.rstrip())
        index.append("%s\t%s\tseed=%s\t%s" % (
            filename, record["id"], record["seed"], record.get("result", "?")))

    (args.out_dir / "INDEX.txt").write_text("\n".join(index) + "\n", encoding="utf-8")
    (args.out_dir / "ALL_BATTLES.txt").write_text(
        "\n\n".join(all_battles) + "\n", encoding="utf-8")
    print("rendered %d battle logs to %s" % (len(records), args.out_dir))


if __name__ == "__main__":
    main()
