#!/usr/bin/env python3
"""Turn a pxx --os=freebsd x86-64 executable into one OpenBSD will run (SPIKE).

    python3 tools/vm/openbsd_spike.py IN.fb OUT.obsd [--maxsys 331]

Three byte patches, measured on OpenBSD 8.0 amd64 on 2026-11-12
(devdocs/progress/working/feature-port-libc-family-openbsd-netbsd-minix.md):

1. The NT_FREEBSD_ABI_TAG note becomes an OpenBSD ident note: same 8-byte
   name length ("FreeBSD\\0" -> "OpenBSD\\0"), type 1, desc 0. Without an
   ident note OpenBSD answers ENOEXEC.
2. The FreeBSD entry's first instruction `mov rsp, rdi` (48 89 fc) becomes
   three NOPs: OpenBSD starts a process with argc at [rsp], as Linux does.
3. A PT_OPENBSD_SYSCALLS (0x65a3dbe9) pin table of {u32 vaddr, u32 sysno} is
   appended and the GNU_STACK phdr is reused to point at it. Each `syscall`
   preceded by `mov eax, imm32` is pinned to that number; every other number
   1..maxsys-1 is pinned to the first generic site (the translator's).
   The kernel DISCARDS the whole table if any entry has sysno <= 0 or
   >= SYS_MAXSYSCALL (331 on 8.0), so only that range is written.

The FreeBSD translator's numbers are then used on OpenBSD; only the calls
that happen to agree (write, exit, getrlimit...) work. Enough for
hello-world, not a port.
"""
import struct
import sys

PT_NOTE, PT_LOAD, PT_GNU_STACK = 4, 1, 0x6474e551
PT_OPENBSD_SYSCALLS = 0x65a3dbe9


def main():
    args = sys.argv[1:]
    maxsys = 331
    if '--maxsys' in args:
        k = args.index('--maxsys')
        maxsys = int(args[k + 1])
        del args[k:k + 2]
    if len(args) != 2:
        sys.exit(__doc__)
    src, dst = args
    b = bytearray(open(src, 'rb').read())
    phoff, = struct.unpack_from('<Q', b, 0x20)
    phnum, = struct.unpack_from('<H', b, 0x38)
    entry, = struct.unpack_from('<Q', b, 0x18)
    note = stack_ph = None
    code = []
    for i in range(phnum):
        o = phoff + i * 56
        t, fl = struct.unpack_from('<II', b, o)
        off, va, _pa, fs = struct.unpack_from('<QQQQ', b, o + 8)
        if t == PT_NOTE:
            note = off
        elif t == PT_GNU_STACK:
            stack_ph = o
        elif t == PT_LOAD and fl & 1:
            code.append((off, va, fs))
    if note is None or stack_ph is None or len(code) != 1:
        sys.exit('not a pxx --os=freebsd executable (note/GNU_STACK/one code segment)')

    # 1. ident note
    namesz, descsz, _ = struct.unpack_from('<III', b, note)
    if bytes(b[note + 12:note + 20]) != b'FreeBSD\0' or namesz != 8 or descsz != 4:
        sys.exit('PT_NOTE is not the FreeBSD ABI tag')
    b[note + 12:note + 20] = b'OpenBSD\0'
    struct.pack_into('<I', b, note + 20, 0)
    b[7] = 0  # EI_OSABI SYSV

    # 2. entry
    coff, cva, cfs = code[0]
    e = coff + (entry - cva)
    if b[e:e + 3] != b'\x48\x89\xfc':
        sys.exit('entry does not start with mov rsp, rdi')
    b[e:e + 3] = b'\x90\x90\x90'

    # 3. pin table
    direct, generic = {}, []
    i = coff
    while True:
        i = b.find(b'\x0f\x05', i, coff + cfs)
        if i < 0:
            break
        no = None
        for back in range(5, 40):
            if b[i - back] == 0xb8:
                no, = struct.unpack_from('<I', b, i - back + 1)
                break
        va = cva + (i - coff)
        if no is None or not 0 < no < maxsys:
            generic.append(va)
        elif no not in direct:
            direct[no] = va
        i += 2
    if not generic:
        sys.exit('no generic syscall site found')
    tab = b''.join(struct.pack('<II', direct.get(n, generic[0]), n)
                   for n in range(1, maxsys))
    while len(b) % 4:
        b.append(0)
    toff = len(b)
    b += tab
    struct.pack_into('<II', b, stack_ph, PT_OPENBSD_SYSCALLS, 4)
    struct.pack_into('<QQQQQQ', b, stack_ph + 8, toff, 0, 0, len(tab), len(tab), 4)
    open(dst, 'wb').write(b)
    print('%s: %d pins, generic site %#x, direct %s' % (
        dst, maxsys - 1, generic[0],
        {n: hex(v) for n, v in sorted(direct.items())}))


if __name__ == '__main__':
    main()
