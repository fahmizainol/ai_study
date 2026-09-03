#!/usr/bin/env python3
"""Extract Ruby source from Pokémon Essentials .rxdata script bundles.

Handles both layouts:
  Scripts.rxdata        [[id, name, deflated_code], ...]
  PluginScripts.rxdata  [[plugin_name, meta_hash, [[script_name, deflated_code], ...]], ...]

Usage:
    python3 extract_rxdata.py <file.rxdata> <outdir> [--list]

    --list   print the manifest only; write nothing

Examples:
    # Which plugins are ACTUALLY compiled into the shipped build?
    python3 extract_rxdata.py "Ashen Frost - Windows/Data/PluginScripts.rxdata" /tmp/x --list

    # Pull a v16 game's whole script set
    python3 extract_rxdata.py "Realidea V4.1/Data/Scripts.rxdata" ./realidea-src
"""
import os
import re
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from marshal_rb import load  # noqa: E402


def safe(name, fallback):
    name = (name or fallback).replace('\\', '/').split('/')[-1]
    name = re.sub(r'[^A-Za-z0-9_.\- ]', '_', name).strip() or fallback
    return name if name.endswith('.rb') else name + '.rb'


def inflate(payload):
    return zlib.decompress(payload.encode('latin1')).decode('utf-8', 'replace')


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    listing = '--list' in sys.argv
    if len(args) < 2 and not (listing and len(args) == 1):
        print(__doc__)
        sys.exit(1)

    src = args[0]
    out = args[1] if len(args) > 1 else None
    data = load(src)

    # Detect layout: plugin bundles have a list as the 3rd element.
    is_plugin_bundle = bool(data) and isinstance(data[0], list) and \
        len(data[0]) >= 3 and isinstance(data[0][2], list)

    total = 0
    if is_plugin_bundle:
        print(f"{len(data)} plugins in {src}\n")
        for plugin_name, meta, scripts in data:
            ver = meta.get('version', '?') if isinstance(meta, dict) else '?'
            print(f"  {plugin_name}  (v{ver})  — {len(scripts)} scripts")
            for scr_name, code in scripts:
                print(f"      {scr_name}")
                if listing:
                    continue
                d = os.path.join(out, safe(plugin_name, 'plugin')[:-3])
                os.makedirs(d, exist_ok=True)
                body = inflate(code)
                open(os.path.join(d, safe(scr_name, f'{total:03d}')), 'w',
                     encoding='utf-8').write(body)
                total += 1
    else:
        print(f"{len(data)} script sections in {src}\n")
        for idx, entry in enumerate(data):
            name = entry[1] if len(entry) > 1 else ''
            code = entry[2] if len(entry) > 2 else None
            if code is None:
                continue
            body = inflate(code)
            label = name or '(unnamed)'
            print(f"  {idx:03d}  {label}  ({len(body.splitlines())} lines)")
            if listing:
                continue
            os.makedirs(out, exist_ok=True)
            open(os.path.join(out, f"{idx:03d}_" + safe(name, 'unnamed')), 'w',
                 encoding='utf-8').write(body)
            total += 1

    if not listing:
        print(f"\nwrote {total} files to {out}")


if __name__ == '__main__':
    main()
