#!/usr/bin/env python3
"""crtl on xtensa issues the time64 syscalls, never the time32 ones.

Builds test/c_xtensa_time64_syscalls.c for hosted xtensa and runs it under
qemu-xtensa -strace. The program must print "time64 ok" (the clock moved across
a 2 ms sleep), and the trace must name none of the time32 calls: clock_gettime,
nanosleep, ppoll, pselect6, utimensat. qemu -strace prints the time64 ones it
cannot name as "Unknown syscall N"; those are expected.
Exits 0, saying so, when qemu-xtensa is absent.
usage: tools/check_xtensa_time64_syscalls.py <compiler> <tmpdir>
feature-xtensa-crtl-uses-the-time64-syscalls
"""
import os
import re
import shutil
import subprocess
import sys

SRC = 'test/c_xtensa_time64_syscalls.c'
TIME32 = ('clock_gettime', 'nanosleep', 'ppoll', 'pselect6', 'utimensat')


def main():
    cc, tmp = sys.argv[1], sys.argv[2]
    qemu = shutil.which('qemu-xtensa')
    exe = os.path.join(tmp, 'c_xt_time64')
    subprocess.run([cc, '--target=xtensa', '--platform=posix', '--xtensa-soft-mulhigh', SRC, exe],
                   check=True, stdout=subprocess.DEVNULL)
    if not qemu:
        print('check_xtensa_time64_syscalls: no qemu-xtensa, NOT run')
        return 0
    out = subprocess.run([qemu, exe], capture_output=True, text=True, timeout=60).stdout
    if out.strip() != 'time64 ok':
        print('check_xtensa_time64_syscalls: FAIL, program said %r' % out.strip())
        return 1
    trace = subprocess.run([qemu, '-strace', exe], capture_output=True, text=True,
                           timeout=60).stderr
    seen = set(re.findall(r'^\d+ ([a-z_0-9]+)\(', trace, re.M))
    bad = sorted(seen.intersection(TIME32))
    if bad:
        print('check_xtensa_time64_syscalls: FAIL, time32 syscalls issued: ' + ', '.join(bad))
        return 1
    if 'clock_gettime64' not in seen:
        print('check_xtensa_time64_syscalls: FAIL, no clock_gettime64 in the trace')
        return 1
    print('check_xtensa_time64_syscalls: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
