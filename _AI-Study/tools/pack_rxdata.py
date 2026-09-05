#!/usr/bin/env python3
"""Insert a script section into a Ruby Marshal 4.8 bundle — counterpart to marshal_rb.py.

Needed because Realidea (v16) has no plugin system and no plaintext Scripts folder: the
only way to add code to it is to rebuild Data/Scripts.rxdata (SIM-SPEC.md §2).

HOW, AND WHY NOT THE OBVIOUS WAY. The obvious approach — parse to Python objects, re-encode
everything — does not survive contact with real bundles. Realidea's was written by a
Ruby 1.9+ Marshal, so its strings are ivar-wrapped (`I"…" :E T`) carrying an encoding, and
21 of them reach that `:E` by *symbol backreference* to the first. Re-encoding naively drops
the wrappers and silently rewrites 1 MB of somebody's game code.

So existing elements are copied as VERBATIM BYTE SLICES and never re-serialised. Only the
count prefix changes, plus the one new element. This is safe here specifically because the
bundle contains no `@` object backreferences (verified by scanning: 330 elements, tags
`[ i " I : ; T` only) — nothing refers to another element by index, so shifting indices
cannot break anything. The new element is written with bare `"` strings, which adds no
symbol and therefore leaves the existing `;0` backrefs pointing where they always did.

`--selftest` re-emits a bundle with no insertion and requires byte-identical output. It is
the reason this is trustworthy: it caught the ivar-string issue on the first run.

Usage:
    python3 pack_rxdata.py --selftest <Scripts.rxdata>
    python3 pack_rxdata.py --insert <in.rxdata> --script <file.rb> --name AI_Probe \
        --before Main --out <out.rxdata>
    python3 pack_rxdata.py --insert <in.rxdata> --script <file.rb> --name Portable_AI \
        --before Main --upsert --out <out.rxdata>
    python3 pack_rxdata.py --remove <in.rxdata> --name Portable_AI --out <out.rxdata>
    python3 pack_rxdata.py --list <Scripts.rxdata>
"""
import argparse
import os
import sys
import tempfile
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from marshal_rb import MarshalReader  # noqa: E402

HEADER = b'\x04\x08'


def w_long(n):
    """Ruby's packed integer encoding (marshal.c w_long)."""
    if n == 0:
        return b'\x00'
    if 0 < n < 123:
        return bytes([n + 5])
    if -124 < n < 0:
        return bytes([(n - 5) & 0xFF])
    out = bytearray()
    v = n
    for i in range(1, 5):
        out.append(v & 0xFF)
        v >>= 8                       # arithmetic shift, as Ruby requires
        if v == 0:
            return bytes([i]) + bytes(out)
        if v == -1:
            return bytes([(-i) & 0xFF]) + bytes(out)
    return bytes([4 if n > 0 else (-4 & 0xFF)]) + bytes(out)


def w_bare_string(b):
    return b'"' + w_long(len(b)) + b


def scan(path):
    """Return (raw, count, spans) where spans are byte ranges of each top-level element."""
    with open(path, 'rb') as fh:
        raw = fh.read()
    if raw[:2] != HEADER:
        raise ValueError('%s: not Marshal 4.8 (magic %r)' % (path, raw[:2]))
    r = MarshalReader(raw[2:])        # reader indexes from the stripped body
    tag = chr(r.byte())
    if tag != '[':
        raise ValueError('%s: root is %r, expected an Array' % (path, tag))
    count = r.long()
    spans = []
    for _ in range(count):
        start = r.i
        r.parse()
        spans.append((start + 2, r.i + 2))   # +2: undo the stripped header offset
    if r.i + 2 != len(raw):
        raise ValueError('%s: %d trailing bytes after the array'
                         % (path, len(raw) - (r.i + 2)))
    return raw, count, spans


def section_names(path):
    from marshal_rb import load
    out = []
    for sec in load(path):
        name = sec[1]
        out.append(name.encode('latin1') if isinstance(name, str) else name)
    return out


def build(raw, spans, insert_at=None, new_elem=None, replace=None, remove=None):
    """replace: {index: element_bytes} — swaps whole elements, leaving all others verbatim."""
    replace = replace or {}
    remove = remove or set()
    count = len(spans) + (1 if new_elem else 0) - len(remove)
    parts = [HEADER, b'[', w_long(count)]
    for i, (s, e) in enumerate(spans):
        if new_elem is not None and i == insert_at:
            parts.append(new_elem)
        if i in remove:
            continue
        parts.append(replace[i] if i in replace else raw[s:e])
    if new_elem is not None and insert_at == len(spans):
        parts.append(new_elem)
    return b''.join(parts)


def make_elem(name, body):
    """A bare-string [0, name, deflate(body)] element — adds no symbol to the table."""
    return b'[' + w_long(3) + b'i' + w_long(0) + \
        w_bare_string(name.encode('utf-8')) + w_bare_string(zlib.compress(body))


def write_atomic(path, data):
    """Replace path only after a complete same-directory write and fsync."""
    target = os.path.abspath(path)
    directory = os.path.dirname(target) or '.'
    fd, temporary = tempfile.mkstemp(prefix='.pack_rxdata-', dir=directory)
    try:
        with os.fdopen(fd, 'wb') as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--selftest')
    ap.add_argument('--list')
    ap.add_argument('--insert')
    ap.add_argument('--remove', help='bundle to remove the last section named --name from')
    ap.add_argument('--script')
    ap.add_argument('--name', default='AI_Probe')
    ap.add_argument('--before')
    ap.add_argument('--upsert', action='store_true',
                    help='replace the last section named --name, or insert it if absent')
    ap.add_argument('--replace', help='name of a section whose body to swap wholesale')
    ap.add_argument('--replace-with', help='file supplying the new body for --replace')
    ap.add_argument('--out')
    a = ap.parse_args()

    if a.list:
        for i, n in enumerate(section_names(a.list)):
            print('%3d  %s' % (i, n.decode('utf-8', 'replace')))
        return

    if a.selftest:
        raw, count, spans = scan(a.selftest)
        rebuilt = build(raw, spans)
        ok = rebuilt == raw
        print('sections      : %d' % count)
        print('original bytes: %d' % len(raw))
        print('rebuilt bytes : %d' % len(rebuilt))
        print('BYTE-IDENTICAL: %s' % ok)
        if not ok:
            for i in range(min(len(raw), len(rebuilt))):
                if raw[i] != rebuilt[i]:
                    print('first diff at %d: %r vs %r'
                          % (i, raw[i:i + 16], rebuilt[i:i + 16]))
                    break
        sys.exit(0 if ok else 1)

    if a.remove:
        if not a.out:
            ap.error('--remove needs --out')
        raw, count, spans = scan(a.remove)
        names = section_names(a.remove)
        target = a.name.encode('utf-8')
        hits = [i for i, name in enumerate(names) if name == target]
        if not hits:
            ap.error('no section named %r; refusing to remove anything' % a.name)
        idx = hits[-1]
        out = build(raw, spans, remove={idx})
        old_pre = spans[0][0]
        new_pre = len(HEADER) + 1 + len(w_long(len(spans) - 1))
        n = spans[idx][0] - old_pre
        assert out[new_pre:new_pre + n] == raw[old_pre:old_pre + n], \
            'untouched sections diverged before index %d' % idx
        write_atomic(a.out, out)
        print('sections %d -> %d; %d -> %d bytes'
              % (count, count - 1, len(raw), len(out)))
        print('  removed %r at index %d' % (a.name, idx))
        return

    if a.insert:
        if not a.out:
            ap.error('--insert needs --out')
        if a.upsert and not a.script:
            ap.error('--upsert needs --script')
        if not a.script and not a.replace:
            ap.error('--insert needs --script and/or --replace')
        raw, count, spans = scan(a.insert)
        names = section_names(a.insert)

        def find(section_name):
            t = section_name.encode('utf-8')
            hits = [i for i, n in enumerate(names) if n == t]
            if not hits:
                ap.error('no section named %r; refusing to guess a position' % section_name)
            return hits[-1]

        elem = None
        idx = count
        replace = {}
        replaced_names = {}
        if a.script:
            with open(a.script, 'rb') as fh:
                elem = make_elem(a.name, fh.read())
            existing = [i for i, n in enumerate(names) if n == a.name.encode('utf-8')]
            if a.upsert and existing:
                idx = existing[-1]
                replace[idx] = elem
                replaced_names[idx] = a.name
                elem = None
            elif a.before:
                idx = find(a.before)

        if a.replace:
            if not a.replace_with:
                ap.error('--replace needs --replace-with')
            with open(a.replace_with, 'rb') as fh:
                replace_idx = find(a.replace)
                replace[replace_idx] = make_elem(a.replace, fh.read())
                replaced_names[replace_idx] = a.replace

        out = build(raw, spans, insert_at=idx, new_elem=elem, replace=replace)
        # Every element before the first one we touch must be byte-identical. Compare from
        # the end of the array header, not from byte 0: the element-count prefix is
        # SUPPOSED to change when a section is added, so a from-zero compare always fails.
        first_touch = min(([idx] if elem is not None else []) + list(replace))
        old_pre = spans[0][0]
        new_pre = len(HEADER) + 1 + len(w_long(len(spans) + (1 if elem else 0)))
        touch_offset = spans[first_touch][0] if first_touch < len(spans) else len(raw)
        n = touch_offset - old_pre
        assert out[new_pre:new_pre + n] == raw[old_pre:old_pre + n], \
            'untouched sections diverged before index %d' % first_touch
        write_atomic(a.out, out)
        print('sections %d -> %d; %d -> %d bytes'
              % (count, count + (1 if elem else 0), len(raw), len(out)))
        if elem:
            print('  inserted %r at index %d' % (a.name, idx))
        for i in sorted(replace):
            print('  replaced %r at index %d' % (replaced_names[i], i))


if __name__ == '__main__':
    main()
