#!/usr/bin/env python3
"""Fail if a named function in a riscv32 ELF object calls its own entry.

    tools/check_rv32_no_self_call.py <obj.o> <func> [<func>...]

Reads the object's symbol table and .text, decodes every JAL (and
auipc+jalr pair with a resolved displacement) inside each named function, and
exits 1 naming any whose target is that function's own first byte. No
toolchain needed, so it runs where the Espressif objdump is not installed.

Written for bug-a-a-dce-cut-backward-call-keeps-its-old-target-and-recurses-on-esp:
a DCE-cut backward call kept its old target, which after compaction was the
start of the calling function, so PXXClassFinalize called itself until the
stack ran out on every Free of a class with a managed field.
"""
import struct, sys


def sext(v, bits):
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


def main():
    if len(sys.argv) < 3:
        print(__doc__.strip().split('\n')[2].strip())
        return 2
    path, names = sys.argv[1], set(sys.argv[2:])
    data = open(path, 'rb').read()
    if data[:4] != b'\x7fELF' or data[4] != 1:
        print('not an ELF32 object: ' + path)
        return 2
    shoff, = struct.unpack_from('<I', data, 0x20)
    shentsize, shnum, shstrndx = struct.unpack_from('<HHH', data, 0x2E)
    secs = []
    for i in range(shnum):
        nm, typ, flg, addr, off, size, link, info, align, ent = struct.unpack_from('<IIIIIIIIII', data, shoff + i * shentsize)
        secs.append((nm, typ, off, size, link, ent))
    shstr = secs[shstrndx]
    def secname(i):
        o = shstr[2] + secs[i][0]
        return data[o:data.index(b'\0', o)].decode()
    funcs = {}
    starts = {}   # section -> every function start in it, for symbols of size 0
    for i, (nm, typ, off, size, link, ent) in enumerate(secs):
        if typ != 2:   # SHT_SYMTAB
            continue
        strtab = secs[link]
        for k in range(size // 16):
            st_name, st_value, st_size, st_info, st_other, st_shndx = struct.unpack_from('<IIIBBH', data, off + k * 16)
            if st_info & 0xF != 2 or st_shndx == 0 or st_shndx >= 0xFF00:   # STT_FUNC, defined
                continue
            o = strtab[2] + st_name
            name = data[o:data.index(b'\0', o)].decode()
            starts.setdefault(st_shndx, set()).add(st_value)
            if name in names:
                funcs[name] = (st_shndx, st_value, st_size)
    bad = 0
    for name in sorted(names):
        if name not in funcs:
            print('%s: not in %s' % (name, path))
            bad += 1
            continue
        shndx, start, size = funcs[name]
        base = secs[shndx][2]
        if size <= 0:
            # pxx emits local function symbols with size 0: run to the next one
            later = [v for v in starts.get(shndx, ()) if v > start]
            size = (min(later) if later else secs[shndx][3]) - start
        pc = start
        prev = None
        while pc + 4 <= start + size:
            w, = struct.unpack_from('<I', data, base + pc)
            if w & 3 != 3:          # a compressed (16-bit) instruction
                pc += 2
                prev = None
                continue
            op = w & 0x7F
            tgt = None
            if op == 0x6F and ((w >> 7) & 0x1F) == 1:          # jal ra, imm
                imm = ((w >> 31) & 1) << 20 | ((w >> 12) & 0xFF) << 12 | ((w >> 20) & 1) << 11 | ((w >> 21) & 0x3FF) << 1
                tgt = pc + sext(imm, 21)
            elif op == 0x67 and ((w >> 7) & 0x1F) == 1 and prev is not None:   # jalr ra, rs1, imm after auipc rs1
                pw, ppc = prev
                if (pw & 0x7F) == 0x17 and ((pw >> 7) & 0x1F) == ((w >> 15) & 0x1F):
                    tgt = ppc + sext(pw & 0xFFFFF000, 32) + sext(w >> 20, 12)
            if tgt == start and pc != start:
                print('%s calls its own entry at offset 0x%x (+0x%x)' % (name, pc, pc - start))
                bad += 1
            prev = (w, pc)
            pc += 4
    if bad:
        return 1
    print('no self call in: ' + ', '.join(sorted(names)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
