#!/usr/bin/env python3
"""xtensa density steps 1-3: right, and smaller.

test/c_density_branch_incdec.c (branch-context compares of every kind, the
`c == 0` fold, x +- k at addi's limits, ++/-- whose value is unused on every
scalar kind) must print what gcc prints (.expected) as a hosted call0
program, and exit with gcc's h & 255 (143) as a windowed --emit-obj linked
with test/c_xtensa_windowed_start.S (-DDENSITY_BARE). Then
test/c_xtensa_density_loop.c's f, windowed, must stay at most MAX
instructions: 74 before (feature-xtensa-codegen-density-before-register-
allocation), 37 after steps 1-3 and the follow-ups. Exits 0, saying so, for an absent tool.
usage: tools/check_xtensa_density.py <compiler> <tmpdir>
"""
import glob
import os
import re
import shutil
import subprocess
import sys

SRC = 'test/c_density_branch_incdec.c'
LOOP = 'test/c_xtensa_density_loop.c'
START = 'test/c_xtensa_windowed_start.S'
WANT_BARE = 143
MAX = 40
HOSTED = ['--target=xtensa', '--platform=posix', '--xtensa-soft-mulhigh', '--xtensa-long-calls']


def main():
    cc, tmp = sys.argv[1], sys.argv[2]
    fails = 0
    exe = os.path.join(tmp, 'c_xtdens_c0')
    subprocess.run([cc] + HOSTED + ['--xtensa-abi=call0', '-Ilib/crtl/include', '-Ilib/crtl/src',
                    SRC, exe], check=True, stdout=subprocess.DEVNULL)
    want = open(SRC[:-2] + '.expected').read()
    qemu = shutil.which('qemu-xtensa')
    if not qemu:
        print('check_xtensa_density: no qemu-xtensa, NOT run')
        return 0
    got = subprocess.run(['tools/run_target.sh', 'xtensa', exe], capture_output=True,
                         text=True, timeout=300).stdout
    if got != want:
        print('check_xtensa_density: call0 FAIL\n--- got\n%s--- want\n%s' % (got, want))
        fails += 1
    bins = sorted(glob.glob(os.path.expanduser(
        '~/.espressif/tools/xtensa-esp-elf/*/xtensa-esp-elf/bin')))
    if not bins:
        print('check_xtensa_density: call0 %s; no xtensa binutils, windowed NOT run'
              % ('FAIL' if fails else 'OK'))
        return 1 if fails else 0
    b = bins[-1] + '/xtensa-esp32s3-elf-'
    obj = os.path.join(tmp, 'c_xtdens_w.o')
    sto = os.path.join(tmp, 'c_xtdens_wst.o')
    elf = os.path.join(tmp, 'c_xtdens_w.elf')
    subprocess.run([cc, '--target=xtensa', '--platform=posix', '--xtensa-soft-mulhigh',
                    '--xtensa-abi=windowed', '--emit-obj', '-DDENSITY_BARE', SRC, obj],
                   check=True, stdout=subprocess.DEVNULL)
    subprocess.run([b + 'as', START, '-o', sto], check=True)
    subprocess.run([b + 'ld', '-e', '_start', '-Ttext=0x10000', sto, obj, '-o', elf], check=True)
    rc = subprocess.run([qemu, elf], timeout=120).returncode
    if rc != WANT_BARE:
        print('check_xtensa_density: windowed FAIL, exit %d, want %d' % (rc, WANT_BARE))
        fails += 1
    lo = os.path.join(tmp, 'c_xtdens_loop.o')
    subprocess.run([cc, '--target=esp32s3', '--freestanding', '--emit-obj', LOOP, lo],
                   check=True, stdout=subprocess.DEVNULL)
    dis = subprocess.run([b + 'objdump', '-d', '--disassemble=f', lo], check=True,
                         capture_output=True, text=True).stdout
    n = len([l for l in dis.splitlines() if re.match(r'^\s+[0-9a-f]+:\s', l)])
    if n == 0 or n > MAX:
        print('check_xtensa_density: f is %d instructions, at most %d wanted (74 before)' % (n, MAX))
        fails += 1
    print('check_xtensa_density: %s (loop f: %d instructions)' % ('FAIL' if fails else 'OK', n))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
