#!/usr/bin/env python3
"""Hosted xtensa issues the PAL syscalls it used to refuse.

test/c_xtensa_pal_syscalls.c on x86-64 and under qemu-xtensa must both print
test/c_xtensa_pal_syscalls.expected (gcc's output), and qemu-xtensa -strace
must name every syscall the xtensa PAL used to answer PAL_ERR_UNSUPPORTED
for without issuing one. A wrong number from the kernel's table would show
as a different name here. Exits 0, saying so, without qemu-xtensa.
usage: tools/check_xtensa_pal_syscalls.py <compiler> <tmpdir>
bug-xtensa-pal-refused-nineteen-syscalls-it-had-numbers-for
"""
import os
import re
import shutil
import subprocess
import sys

SRC = 'test/c_xtensa_pal_syscalls.c'
WANT_CALLS = ['uname', 'times', 'prlimit64', 'getrusage', 'getpgid', 'getsid', 'setpgid',
              'getpriority', 'setpriority', 'getgroups', 'rt_sigprocmask', 'setitimer',
              'fdatasync', 'sync']


def main():
    cc, tmp = sys.argv[1], sys.argv[2]
    want = open('test/c_xtensa_pal_syscalls.expected').read()
    x64 = os.path.join(tmp, 'c_xt_pal_x64')
    xt = os.path.join(tmp, 'c_xt_pal_xt')
    subprocess.run([cc, SRC, x64], check=True, stdout=subprocess.DEVNULL)
    subprocess.run([cc, '--target=xtensa', '--platform=posix', '--xtensa-soft-mulhigh', SRC, xt],
                   check=True, stdout=subprocess.DEVNULL)
    got = subprocess.run([x64], capture_output=True, text=True, timeout=60).stdout
    if got != want:
        print('check_xtensa_pal_syscalls: FAIL, x86-64 printed %r' % got)
        return 1
    qemu = shutil.which('qemu-xtensa')
    if not qemu:
        print('check_xtensa_pal_syscalls: no qemu-xtensa, xtensa half NOT run')
        return 0
    r = subprocess.run([qemu, '-strace', xt], capture_output=True, text=True, timeout=60)
    if r.stdout != want:
        print('check_xtensa_pal_syscalls: FAIL, xtensa printed %r' % r.stdout)
        return 1
    seen = set(re.findall(r'^\d+ ([a-z_0-9]+)\(', r.stderr, re.M))
    missing = [c for c in WANT_CALLS if c not in seen]
    if missing:
        print('check_xtensa_pal_syscalls: FAIL, no %s in the xtensa trace' % ' '.join(missing))
        return 1
    print('check_xtensa_pal_syscalls: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
