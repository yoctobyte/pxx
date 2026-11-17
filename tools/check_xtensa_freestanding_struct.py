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
    # extern declarations take no .bss: two objects, interleaved live and
    # extern globals, run; and the declaring object's .bss stays small
    objs = []
    for part, src in (('a', 'test/c_xtensa_extern_bss_a.c'),
                      ('b', 'test/c_xtensa_extern_bss_b.c')):
        o = os.path.join(tmp, 'c_xteb_%s.o' % part)
        subprocess.run([cc, '--target=esp32s3', '--xtensa-abi=call0', '--freestanding',
                        '--emit-obj', src, o],
                       check=True, stdout=subprocess.DEVNULL)
        objs.append(o)
    elf2 = os.path.join(tmp, 'c_xteb.elf')
    subprocess.run([b + 'ld', '-e', '_start', '-Ttext=0x10000', st] + objs + ['-o', elf2],
                   check=True)
    rc = subprocess.run([qemu, elf2], timeout=60).returncode
    if rc != 189:
        print('check_xtensa_freestanding_struct: extern-bss FAIL, exit %d, want 189' % rc)
        return 1
    hdrs = subprocess.run([b + 'readelf', '-SW', objs[0]], check=True, capture_output=True,
                          text=True).stdout
    for line in hdrs.splitlines():
        p = line.split()
        if '.bss' in p:
            k = p.index('.bss')
            size = int(p[k + 4], 16)
            if size >= 256:
                print('check_xtensa_freestanding_struct: extern-bss FAIL, .bss is %d bytes'
                      ' (the extern declarations kept their storage)' % size)
                return 1
    # a struct returned by an EXTERN callee (another object), direct and
    # through a function pointer: the caller must pass the hidden result
    # pointer, and on call0 the callee address must not overwrite it in a8
    objs = []
    for part, src in (('a', 'test/c_xtensa_extern_structret_a.c'),
                      ('b', 'test/c_xtensa_extern_structret_b.c')):
        o = os.path.join(tmp, 'c_xtsr_%s.o' % part)
        subprocess.run([cc, '--target=esp32s3', '--xtensa-abi=call0', '--freestanding',
                        '--emit-obj', src, o], check=True, stdout=subprocess.DEVNULL)
        subprocess.run([cc, '--target=esp32s3', '--freestanding', '--emit-obj', src,
                        o + '.w.o'], check=True, stdout=subprocess.DEVNULL)
        objs.append(o)
    elf3 = os.path.join(tmp, 'c_xtsr.elf')
    subprocess.run([b + 'ld', '-e', '_start', '-Ttext=0x10000', st] + objs + ['-o', elf3],
                   check=True)
    rc = subprocess.run([qemu, elf3], timeout=60).returncode
    if rc != 32:
        print('check_xtensa_freestanding_struct: extern struct return FAIL, exit %d,'
              ' want 32' % rc)
        return 1
    print('check_xtensa_freestanding_struct: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
