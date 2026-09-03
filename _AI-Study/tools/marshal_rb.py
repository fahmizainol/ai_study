"""Minimal Ruby Marshal 4.8 reader — enough for RPG Maker XP / Pokémon Essentials .rxdata.

Why this exists: scanning .rxdata for zlib headers (0x78 0x9c ...) LOOKS like it works and
silently drops sections. During the 2026-09-03 AI study that approach missed an entire
15,000-line plugin, which nearly produced a wrong conclusion. Parse the container properly.

Strings are decoded as latin1 so that byte payloads (deflated script code) round-trip
losslessly: recover them with `s.encode('latin1')` before `zlib.decompress`.

Usage:
    from marshal_rb import load
    data = load('Data/PluginScripts.rxdata')
"""


class MarshalReader:
    def __init__(self, data):
        self.d = data
        self.i = 0
        self.syms = []   # symbol table for ';' backrefs
        self.objs = []   # object table for '@' backrefs

    def byte(self):
        b = self.d[self.i]
        self.i += 1
        return b

    def sbyte(self):
        b = self.byte()
        return b - 256 if b > 127 else b

    def long(self):
        """Ruby's packed integer encoding."""
        c = self.sbyte()
        if c == 0:
            return 0
        if c > 4:
            return c - 5
        if c < -4:
            return c + 5
        n = abs(c)
        if c > 0:
            v = 0
            for k in range(n):
                v |= self.byte() << (8 * k)
        else:
            v = -1
            for k in range(n):
                v &= ~(0xFF << (8 * k))
                v |= self.byte() << (8 * k)
        return v

    def parse(self):
        t = chr(self.byte())
        if t == '0':
            return None
        if t == 'T':
            return True
        if t == 'F':
            return False
        if t == 'i':
            return self.long()
        if t == ':':                       # symbol
            n = self.long()
            s = self.d[self.i:self.i + n].decode('utf-8', 'replace')
            self.i += n
            self.syms.append(s)
            return s
        if t == ';':                       # symbol backref
            return self.syms[self.long()]
        if t == '@':                       # object backref
            return self.objs[self.long()]
        if t == '"':                       # string — latin1 keeps bytes recoverable
            n = self.long()
            v = self.d[self.i:self.i + n].decode('latin1')
            self.i += n
            self.objs.append(v)
            return v
        if t == 'I':                       # ivar-wrapped object
            v = self.parse()
            for _ in range(self.long()):
                self.parse()
                self.parse()
            return v
        if t == '[':
            n = self.long()
            a = []
            self.objs.append(a)
            for _ in range(n):
                a.append(self.parse())
            return a
        if t == '{':
            n = self.long()
            h = {}
            self.objs.append(h)
            for _ in range(n):
                k = self.parse()
                h[str(k)] = self.parse()
            return h
        if t == 'o':                       # plain object -> dict of ivars
            self.parse()                   # class name
            n = self.long()
            o = {}
            self.objs.append(o)
            for _ in range(n):
                k = self.parse()
                o[str(k)] = self.parse()
            return o
        if t == 'u':                       # userdef (Table, Tone, ...) — skipped
            self.parse()
            self.i += self.long()
            return None
        raise ValueError(f"unhandled Marshal type {t!r} at offset {self.i}")


def load(path):
    d = open(path, 'rb').read()
    if d[:2] != b'\x04\x08':
        raise ValueError(f"{path}: not Marshal 4.8 (magic {d[:2]!r})")
    return MarshalReader(d[2:]).parse()
