#!/usr/bin/env python3
"""The hosted xtensa heap maps memory in small pieces (no-MMU Nilix).

test/c_xtensa_heap_arenas.c under qemu-xtensa -strace: it must print gcc's
"sum 10696", and no mmap may exceed 256 KiB -- the old runtime asked for
256 MiB first and kept whatever a halving loop got, all of it real memory
without an MMU. Exactly one 64 KiB arena serves the 200 small allocations.
Exits 0, saying so, without qemu-xtensa.
usage: tools/check_xtensa_heap_arenas.py <compiler> <tmpdir>
feature-xtensa-heap-grows-in-small-arenas-on-no-mmu
"""
import os
import re
import shutil
import subprocess
import sys


def main():
    cc, tmp = sys.argv[1], sys.argv[2]
    exe = os.path.join(tmp, 'c_xt_heap')
    subprocess.run([cc, '--target=xtensa', '--platform=posix', '--xtensa-soft-mulhigh',
                    'test/c_xtensa_heap_arenas.c', exe], check=True, stdout=subprocess.DEVNULL)
    qemu = shutil.which('qemu-xtensa')
    if not qemu:
        print('check_xtensa_heap_arenas: no qemu-xtensa, NOT run')
        return 0
    r = subprocess.run([qemu, '-strace', exe], capture_output=True, text=True, timeout=60)
    if r.stdout.strip() != 'sum 10696':
        print('check_xtensa_heap_arenas: FAIL, program said %r' % r.stdout.strip())
        return 1
    sizes = [int(m) for m in re.findall(r' mmap2?\([^,]*,(\d+),', r.stderr)]
    if not sizes or max(sizes) > 262144:
        print('check_xtensa_heap_arenas: FAIL, mappings %s' % sizes)
        return 1
    if sizes.count(65536) != 1:
        print('check_xtensa_heap_arenas: FAIL, want one 64 KiB arena, mappings %s' % sizes)
        return 1
    print('check_xtensa_heap_arenas: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
