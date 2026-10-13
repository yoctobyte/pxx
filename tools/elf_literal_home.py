#!/usr/bin/env python3
"""elf_literal_home.py LINKED.elf MARKER

Where did a string literal land in a LINKED ELF32 image, and who points at it?

Prints one line:  home=<section> flags=<A|AW|AX..> refs=<section>,<section>...
  home  - the SHF_ALLOC PROGBITS section holding MARKER's bytes
  refs  - every SHF_ALLOC PROGBITS section containing MARKER's address as a
          little-endian 32-bit word at any offset (a code literal slot, a
          pointer in a table), or -- riscv32 objects since 2026-10-13 -- built
          by a `lui rd, %hi; addi rd, rd, %lo` pair (R_RISCV_HI20/LO12_I)

Exit 1 when MARKER is absent, occurs twice (the answer would be a guess), or
nothing points at it -- a literal with no reference proves nothing about the
relocations, which are the thing under test.

Why the address and not a disassembly: a relocation with the wrong symbol or
addend still links, and the image then points somewhere else. The only
observable that separates right from wrong is that the word a reference holds
equals the address the bytes were placed at, so compare exactly that.
"""
import struct
import sys


def sections(img):
    if img[:4] != b'\x7fELF' or img[4] != 1:
        sys.exit('elf_literal_home: not an ELF32 file')
    shoff, = struct.unpack_from('<I', img, 0x20)
    shentsize, shnum, shstrndx = struct.unpack_from('<HHH', img, 0x2E)
    raw = [struct.unpack_from('<IIIIIIIIII', img, shoff + i * shentsize)
           for i in range(shnum)]
    stroff = raw[shstrndx][4]
    out = []
    for name, typ, flags, addr, off, size, *_ in raw:
        end = img.index(b'\0', stroff + name)
        out.append((img[stroff + name:end].decode(), typ, flags, addr, off, size))
    return out


def hilo_builds(body, va):
    """Does a riscv `lui rd, hi` + `addi rd, rd, lo` pair in body make va?
    Every 2-byte offset: linked code beside ours may be compressed."""
    for i in range(0, len(body) - 7, 2):
        w, = struct.unpack_from('<I', body, i)
        if w & 0x7f != 0x37:
            continue
        rd = (w >> 7) & 31
        w2, = struct.unpack_from('<I', body, i + 4)
        if w2 & 0x707f != 0x13 or (w2 >> 7) & 31 != rd or (w2 >> 15) & 31 != rd:
            continue
        lo = w2 >> 20
        if lo & 0x800:
            lo -= 0x1000
        if ((w & 0xfffff000) + lo) & 0xffffffff == va:
            return True
    return False


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    img = open(sys.argv[1], 'rb').read()
    marker = sys.argv[2].encode()
    secs = [s for s in sections(img) if s[1] == 1 and s[2] & 2]  # PROGBITS, ALLOC
    hits = []
    for name, _, flags, addr, off, size in secs:
        body = img[off:off + size]
        i = body.find(marker)
        while i >= 0:
            hits.append((name, flags, addr + i))
            i = body.find(marker, i + 1)
    if len(hits) != 1:
        print('elf_literal_home: %s occurs %d times in allocated sections'
              % (sys.argv[2], len(hits)))
        sys.exit(1)
    home, flags, va = hits[0]
    word = struct.pack('<I', va)
    refs = []
    for name, _, _, addr, off, size in secs:
        body = img[off:off + size]
        if body.find(word) >= 0 or hilo_builds(body, va):   # any offset: a riscv
            refs.append(name)                     # literal can sit after a 2-byte insn
    fl = 'A' + ('W' if flags & 1 else '') + ('X' if flags & 4 else '')
    print('home=%s flags=%s refs=%s' % (home, fl, ','.join(refs) or '-'))
    sys.exit(0 if refs else 1)


if __name__ == '__main__':
    main()
