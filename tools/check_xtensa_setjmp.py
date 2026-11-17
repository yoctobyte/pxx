#!/usr/bin/env python3
"""C setjmp/longjmp on xtensa, call0 and windowed.

test/c_xtensa_setjmp.c must print what gcc prints (c_xtensa_setjmp.expected):
call0 as a hosted program, windowed as an --emit-obj linked `ld -e app_main`.
Exits 0, saying so, without qemu-xtensa or the xtensa binutils.
usage: tools/check_xtensa_setjmp.py <compiler> <tmpdir>
feature-xtensa-c-setjmp-longjmp
"""
import glob
import os
import shutil
import subprocess
import sys

SRC = 'test/c_xtensa_setjmp.c'
BASE = ['--target=xtensa', '--platform=posix', '--xtensa-soft-mulhigh']


def main():
    cc, tmp = sys.argv[1], sys.argv[2]
    want = open('test/c_xtensa_setjmp.expected').read().strip()
    exe = os.path.join(tmp, 'c_xt_sj_c0')
    subprocess.run([cc] + BASE + [SRC, exe], check=True, stdout=subprocess.DEVNULL)
    qemu = shutil.which('qemu-xtensa')
    if not qemu:
        print('check_xtensa_setjmp: no qemu-xtensa, NOT run')
        return 0
    out = subprocess.run([qemu, exe], capture_output=True, text=True, timeout=60).stdout.strip()
    if out != want:
        print('check_xtensa_setjmp: FAIL, call0 said %r' % out)
        return 1
    bins = sorted(glob.glob(os.path.expanduser(
        '~/.espressif/tools/xtensa-esp-elf/*/xtensa-esp-elf/bin/xtensa-esp32s3-elf-ld')))
    if not bins:
        print('check_xtensa_setjmp: call0 OK; no xtensa binutils, windowed NOT run')
        return 0
    obj, elf = os.path.join(tmp, 'c_xt_sj_w.o'), os.path.join(tmp, 'c_xt_sj_w.elf')
    subprocess.run([cc] + BASE + ['--xtensa-abi=windowed', '--no-ro-data', '--emit-obj', SRC, obj],
                   check=True, stdout=subprocess.DEVNULL)
    subprocess.run([bins[-1], '-e', 'app_main', '-Ttext=0x10000', obj, '-o', elf], check=True)
    out = subprocess.run([qemu, elf], capture_output=True, text=True, timeout=60).stdout.strip()
    if out != want:
        print('check_xtensa_setjmp: FAIL, windowed said %r' % out)
        return 1
    print('check_xtensa_setjmp: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
