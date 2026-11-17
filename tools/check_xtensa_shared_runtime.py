#!/usr/bin/env python3
"""Several xtensa objects link against one runtime object (--shared-runtime).

test/c_xtensa_srt_{main,part}.c built --shared-runtime --emit-obj (windowed),
the runtime object built from lib/crtl/include/pxx/runtime_all.h as
ElfRtProvide builds it, linked `ld -e app_main`, run under qemu-xtensa:
errno, stdout, environ and the heap must be ONE across the objects, and the
stdarg/setjmp copies every object carries must not collide (they are WEAK).
Then the same three link as a PIE. Exits 0, saying so, without qemu-xtensa or
the xtensa binutils.
usage: tools/check_xtensa_shared_runtime.py <compiler> <tmpdir>
feature-xtensa-shared-runtime-objects-link
"""
import glob
import os
import shutil
import subprocess
import sys

F = ['--target=xtensa', '--platform=posix', '--xtensa-soft-mulhigh', '--xtensa-abi=windowed',
     '--no-ro-data', '--emit-obj']
WANT = 'dup shared open -1 errno 2 same-stdout 1 env yes sum 15'


def main():
    cc, tmp = sys.argv[1], sys.argv[2]
    objs = []
    for src in ('test/c_xtensa_srt_main.c', 'test/c_xtensa_srt_part.c'):
        o = os.path.join(tmp, os.path.basename(src)[:-2] + '.o')
        subprocess.run([cc] + F + ['--shared-runtime', src, o], check=True,
                       stdout=subprocess.DEVNULL)
        objs.append(o)
    rtc, rto = os.path.join(tmp, 'c_xt_srt_rt.c'), os.path.join(tmp, 'c_xt_srt_rt.o')
    with open(rtc, 'w') as f:
        f.write('#include <pxx/runtime_all.h>\n')
    subprocess.run([cc] + F + [rtc, rto], check=True, stdout=subprocess.DEVNULL)
    objs.append(rto)
    bins = sorted(glob.glob(os.path.expanduser(
        '~/.espressif/tools/xtensa-esp-elf/*/xtensa-esp-elf/bin/xtensa-esp32s3-elf-ld')))
    qemu = shutil.which('qemu-xtensa')
    if not bins or not qemu:
        print('check_xtensa_shared_runtime: no xtensa binutils or qemu-xtensa, NOT run')
        return 0
    elf = os.path.join(tmp, 'c_xt_srt.elf')
    r = subprocess.run([bins[-1], '-e', 'app_main', '-Ttext=0x10000'] + objs + ['-o', elf],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print('check_xtensa_shared_runtime: FAIL, ld: ' + (r.stderr.strip().splitlines() or ['?'])[-1])
        return 1
    r = subprocess.run([qemu, elf], capture_output=True, text=True, timeout=60,
                       env=dict(os.environ, PXXT='yes'))
    if r.stdout.strip() != WANT or r.returncode != 2:
        print('check_xtensa_shared_runtime: FAIL, got %r exit %d' % (r.stdout.strip(), r.returncode))
        return 1
    pie = os.path.join(tmp, 'c_xt_srt.pie')
    r = subprocess.run([bins[-1], '-pie', '--no-dynamic-linker', '-e', 'app_main', '-T',
                        'test/xtensa_pie_prog.ld'] + objs + ['-o', pie], capture_output=True, text=True)
    if r.returncode != 0:
        print('check_xtensa_shared_runtime: FAIL, PIE link: ' + (r.stderr.strip().splitlines() or ['?'])[0])
        return 1
    print('check_xtensa_shared_runtime: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
