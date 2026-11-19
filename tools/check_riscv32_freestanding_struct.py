#!/usr/bin/env python3
"""Struct copy/zero and extern struct returns in a freestanding riscv32 object, RUN.

The riscv32 sibling of check_xtensa_freestanding_struct.py. Compiles the same
C sources with --target=esp32c3 --freestanding --emit-obj, links each with
test/c_riscv32_freestanding_start.S (a _start that calls check() and exits
with its value) using Espressif's riscv32 binutils, and runs the result under
qemu-riscv32 (user mode). The exit status must be gcc's:
  - c_xtensa_freestanding_struct.c: 81 (struct = {0}, assignment, return by
    value, an odd size, a misaligned copy -- no PXXMemZero/PXXMemMove in a
    freestanding object, so Rv32InlineMem);
  - c_xtensa_extern_structret_{a,b}.c: 32 (a struct returned by a function in
    ANOTHER pxx object needs the hidden result pointer, Rv32CallHasHiddenDest).
Linked with --no-relax: the _start never sets gp, and relaxation would turn
`la` into a gp-relative access. Exits 0, saying so, when a tool is absent.
usage: tools/check_riscv32_freestanding_struct.py <compiler> <tmpdir>
bug-c-struct-copy-and-zero-in-a-freestanding-riscv32-object
"""
import glob
import os
import shutil
import subprocess
import sys

START = 'test/c_riscv32_freestanding_start.S'
CASES = [
    ('struct', ['test/c_xtensa_freestanding_struct.c'], 81),
    ('extern_structret', ['test/c_xtensa_extern_structret_a.c',
                          'test/c_xtensa_extern_structret_b.c'], 32),
]


def main():
    cc, tmp = sys.argv[1], sys.argv[2]
    objs_by_case = {}
    for name, srcs, _ in CASES:
        objs = []
        for i, src in enumerate(srcs):
            o = os.path.join(tmp, 'c_rvfs_%s_%d.o' % (name, i))
            subprocess.run([cc, '--target=esp32c3', '--freestanding', '--emit-obj', src, o],
                           check=True, stdout=subprocess.DEVNULL)
            objs.append(o)
        objs_by_case[name] = objs
    bins = sorted(glob.glob(os.path.expanduser(
        '~/.espressif/tools/riscv32-esp-elf/*/riscv32-esp-elf/bin')))
    qemu = shutil.which('qemu-riscv32')
    if not bins or not qemu:
        print('check_riscv32_freestanding_struct: built; no riscv32 binutils or '
              'qemu-riscv32, NOT run')
        return 0
    b = bins[-1] + '/riscv32-esp-elf-'
    st = os.path.join(tmp, 'c_rvfs_start.o')
    subprocess.run([b + 'as', '-march=rv32imc', START, '-o', st], check=True)
    bad = 0
    for name, _, want in CASES:
        elf = os.path.join(tmp, 'c_rvfs_%s.elf' % name)
        subprocess.run([b + 'ld', '--no-relax', '-e', '_start', '-Ttext=0x10000', st]
                       + objs_by_case[name] + ['-o', elf], check=True)
        rc = subprocess.run([qemu, elf], timeout=60).returncode
        if rc != want:
            print('check_riscv32_freestanding_struct: %s FAIL, exit %d, want %d'
                  % (name, rc, want))
            bad = 1
    if bad:
        return 1
    print('check_riscv32_freestanding_struct: OK (struct 81, extern struct return 32)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
