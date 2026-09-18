#!/usr/bin/env python3
"""elf_literal_home.py LINKED.elf MARKER

Where did a string literal land in a LINKED ELF32 image, and who points at it?

Prints one line:  home=<section> flags=<A|AW|AX..> refs=<section>,<section>...
  home  - the SHF_ALLOC PROGBITS section holding MARKER's bytes
  refs  - every SHF_ALLOC PROGBITS section containing MARKER's address as a
          little-endian 32-bit word at any offset (a code literal slot, a
          pointer in a table)

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
        if img[off:off + size].find(word) >= 0:   # any offset: a riscv literal
            refs.append(name)                     # can sit after a 2-byte insn
    fl = 'A' + ('W' if flags & 1 else '') + ('X' if flags & 4 else '')
    print('home=%s flags=%s refs=%s' % (home, fl, ','.join(refs) or '-'))
    sys.exit(0 if refs else 1)


if __name__ == '__main__':
    main()
