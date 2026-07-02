#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Emit a minimal static `exit(42)` ELF for a target architecture.

    tools/gen_arch_probe.py <i386|aarch64|arm32> <outfile>

Used by `make qemu-env-check` to prove the QEMU user-mode environment
actually *executes* foreign code (an emulator can be installed yet broken
by binfmt/library issues; --version proves nothing). Also a byte-level
reference of what each future backend's ELF writer must produce: machine
id, class, and the target's exit syscall convention.
"""
import struct
import sys

VADDR = 0x400000


def elf64(machine, code):
    ehsize, phsize = 64, 56
    entry = VADDR + ehsize + phsize
    total = ehsize + phsize + len(code)
    eh = struct.pack('<4sBBBBB7xHHIQQQIHHHHHH',
                     b'\x7fELF', 2, 1, 1, 0, 0,
                     2, machine, 1,
                     entry, ehsize, 0, 0,
                     ehsize, phsize, 1, 0, 0, 0)
    ph = struct.pack('<IIQQQQQQ', 1, 5, 0, VADDR, VADDR, total, total, 0x10000)
    return eh + ph + code


def elf32(machine, code):
    ehsize, phsize = 52, 32
    entry = VADDR + ehsize + phsize
    total = ehsize + phsize + len(code)
    eh = struct.pack('<4sBBBBB7xHHIIIIIHHHHHH',
                     b'\x7fELF', 1, 1, 1, 0, 0,
                     2, machine, 1,
                     entry, ehsize, 0, 0,
                     ehsize, phsize, 1, 0, 0, 0)
    # p_offset 0: map the whole file; p_offset must equal p_vaddr mod pagesize.
    ph = struct.pack('<IIIIIIII', 1, 0, VADDR, VADDR, total, total, 5, 0x10000)
    return eh + ph + code


PROBES = {
    # exit(42), raw syscall, no libc.
    'aarch64': lambda: elf64(183, struct.pack('<III',
        0xD2800BA8,    # movz x8, #93   (exit)
        0xD2800540,    # movz x0, #42
        0xD4000001)),  # svc  #0
    'arm32': lambda: elf32(40, struct.pack('<III',
        0xE3A07001,    # mov r7, #1     (exit)
        0xE3A0002A,    # mov r0, #42
        0xEF000000)),  # svc 0
    'i386': lambda: elf32(3,
        b'\xb8\x01\x00\x00\x00'    # mov eax, 1  (exit)
        b'\xbb\x2a\x00\x00\x00'    # mov ebx, 42
        b'\xcd\x80'),              # int 0x80
}


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in PROBES:
        sys.exit(f'usage: {sys.argv[0]} <{"|".join(PROBES)}> <outfile>')
    with open(sys.argv[2], 'wb') as f:
        f.write(PROBES[sys.argv[1]]())


if __name__ == '__main__':
    main()
