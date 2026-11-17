#!/usr/bin/env python3
"""vfork on xtensa is a real vfork, on both ABIs.

test/c_xtensa_vfork.c, call0 as a hosted program (must print
"vfork check 77 system 5") and windowed as an --emit-obj linked with
test/c_xtensa_windowed_start.S (must exit 77). Under qemu -strace every clone
must carry CLONE_VM|CLONE_VFORK: qemu runs a vfork as a fork, so the result
alone would pass the old fork() too. Exits 0, saying so, when qemu-xtensa or
the xtensa binutils (scratch: ~/.espressif) are absent.
usage: tools/check_xtensa_vfork.py <compiler> <tmpdir>
feature-crtl-a-real-vfork-on-xtensa
"""
import glob
import os
import re
import shutil
import subprocess
import sys

SRC = 'test/c_xtensa_vfork.c'
START = 'test/c_xtensa_windowed_start.S'


def clones(qemu, exe):
    tr = subprocess.run([qemu, '-strace', exe], capture_output=True, text=True, timeout=60).stderr
    return re.findall(r' clone\(([^,]*),', tr)


def vfork_flags_ok(name, cl):
    if not cl:
        print('check_xtensa_vfork: FAIL, %s: no clone in the trace' % name)
        return False
    bad = [c for c in cl if 'CLONE_VM' not in c or 'CLONE_VFORK' not in c]
    if bad:
        print('check_xtensa_vfork: FAIL, %s: clone without CLONE_VM|CLONE_VFORK: %s' % (name, bad[0]))
        return False
    return True


def main():
    cc, tmp = sys.argv[1], sys.argv[2]
    qemu = shutil.which('qemu-xtensa')
    exe = os.path.join(tmp, 'c_xt_vfork_c0')
    subprocess.run([cc, '--target=xtensa', '--platform=posix', '--xtensa-soft-mulhigh', SRC, exe],
                   check=True, stdout=subprocess.DEVNULL)
    if not qemu:
        print('check_xtensa_vfork: no qemu-xtensa, NOT run')
        return 0
    out = subprocess.run([qemu, exe], capture_output=True, text=True, timeout=60).stdout.strip()
    if out != 'vfork check 77 system 5':
        print('check_xtensa_vfork: FAIL, call0 said %r' % out)
        return 1
    if not vfork_flags_ok('call0', clones(qemu, exe)):
        return 1
    bins = sorted(glob.glob(os.path.expanduser(
        '~/.espressif/tools/xtensa-esp-elf/*/xtensa-esp-elf/bin/xtensa-esp32s3-elf-ld')))
    if not bins:
        print('check_xtensa_vfork: call0 OK; no xtensa binutils, windowed NOT run')
        return 0
    b = bins[-1][:-len('ld')]
    obj = os.path.join(tmp, 'c_xt_vfork_w.o')
    sto = os.path.join(tmp, 'c_xt_vfork_wstart.o')
    elf = os.path.join(tmp, 'c_xt_vfork_w.elf')
    subprocess.run([cc, '--target=xtensa', '--platform=posix', '--xtensa-soft-mulhigh',
                    '--xtensa-abi=windowed', '--emit-obj', SRC, obj], check=True, stdout=subprocess.DEVNULL)
    subprocess.run([b + 'as', START, '-o', sto], check=True)
    subprocess.run([b + 'ld', '-e', '_start', '-Ttext=0x10000', sto, obj, '-o', elf], check=True)
    rc = subprocess.run([qemu, elf], timeout=60).returncode
    if rc != 77:
        print('check_xtensa_vfork: FAIL, windowed exit %d, want 77' % rc)
        return 1
    if not vfork_flags_ok('windowed', clones(qemu, elf)):
        return 1
    print('check_xtensa_vfork: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
