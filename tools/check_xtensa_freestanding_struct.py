#!/usr/bin/env python3
"""Struct copy/zero in a freestanding xtensa object, RUN.

Compiles test/c_xtensa_freestanding_struct.c with --target=esp32s3
--xtensa-abi=call0 --freestanding --emit-obj (call0, because qemu-xtensa user
mode runs call0 only), links it with test/c_xtensa_freestanding_start.S (a
_start that calls check() and exits with its value) by Espressif's binutils,
and runs it under qemu-xtensa. The exit status must be 81, check() & 255 as
gcc computes it. Also compiles the windowed form, which must build.
Exits 0, saying so, when a tool is absent.
usage: tools/check_xtensa_freestanding_struct.py <compiler> <tmpdir>
bug-c-struct-copy-and-zero-in-a-freestanding-xtensa-object
"""
import glob
import os
import shutil
import subprocess
import sys

SRC = 'test/c_xtensa_freestanding_struct.c'
START = 'test/c_xtensa_freestanding_start.S'
WANT = 81


def main():
    cc, tmp = sys.argv[1], sys.argv[2]
    subprocess.run([cc, '--target=esp32s3', '--freestanding', '--emit-obj', SRC,
                    os.path.join(tmp, 'c_xtfs_w.o')], check=True, stdout=subprocess.DEVNULL)
    bins = sorted(glob.glob(os.path.expanduser(
        '~/.espressif/tools/xtensa-esp-elf/*/xtensa-esp-elf/bin')))
    qemu = shutil.which('qemu-xtensa')
    if not bins or not qemu:
        print('check_xtensa_freestanding_struct: no xtensa binutils or qemu-xtensa, NOT run')
        return 0
    b = bins[-1] + '/xtensa-esp32s3-elf-'
    obj = os.path.join(tmp, 'c_xtfs.o')
    st = os.path.join(tmp, 'c_xtfs_start.o')
    elf = os.path.join(tmp, 'c_xtfs.elf')
    subprocess.run([cc, '--target=esp32s3', '--xtensa-abi=call0', '--freestanding', '--emit-obj',
                    SRC, obj], check=True, stdout=subprocess.DEVNULL)
    subprocess.run([b + 'as', START, '-o', st], check=True)
    subprocess.run([b + 'ld', '-e', '_start', '-Ttext=0x10000', st, obj, '-o', elf], check=True)
    rc = subprocess.run([qemu, elf], timeout=60).returncode
    if rc != WANT:
        print('check_xtensa_freestanding_struct: FAIL, exit %d, want %d' % (rc, WANT))
        return 1
    print('check_xtensa_freestanding_struct: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
