#!/usr/bin/env python3
"""A windowed xtensa posix object is a process: app_main at .text+0 runs main.

test/c_xtensa_posix_main.c as --emit-obj, linked `ld -e app_main` and run
under qemu-xtensa with an argument and an environment variable: it must print
argc, argv[1], the variable and the atexit line, and exit 3 (main's result,
which the unseeded root window used to lose). Then the same object links as a
PIE (test/xtensa_pie_prog.ld, -e app_main). And an object with no main
exports app_main WEAK, so it cannot clash with the one that has it. And
built --shared-runtime against a runtime object, main's return still runs the
atexit handler, which now sits in the runtime object's table
(bug-xtensa-shared-runtime-objects-skip-atexit-handlers). Exits 0,
saying so, without qemu-xtensa or the xtensa binutils.
usage: tools/check_xtensa_posix_main.py <compiler> <tmpdir>
feature-xtensa-posix-objects-get-a-process-entry
"""
import glob
import os
import shutil
import subprocess
import sys

FLAGS = ['--target=xtensa', '--platform=posix', '--xtensa-soft-mulhigh',
         '--xtensa-abi=windowed', '--no-ro-data', '--emit-obj']


def main():
    cc, tmp = sys.argv[1], sys.argv[2]
    bins = sorted(glob.glob(os.path.expanduser(
        '~/.espressif/tools/xtensa-esp-elf/*/xtensa-esp-elf/bin/xtensa-esp32s3-elf-ld')))
    qemu = shutil.which('qemu-xtensa')
    obj = os.path.join(tmp, 'c_xt_pmain.o')
    subprocess.run([cc] + FLAGS + ['test/c_xtensa_posix_main.c', obj], check=True,
                   stdout=subprocess.DEVNULL)
    if not bins or not qemu:
        print('check_xtensa_posix_main: no xtensa binutils or qemu-xtensa, NOT run')
        return 0
    b = bins[-1][:-len('ld')]
    elf = os.path.join(tmp, 'c_xt_pmain.elf')
    subprocess.run([b + 'ld', '-e', 'app_main', '-Ttext=0x10000', obj, '-o', elf], check=True)
    env = dict(os.environ, PXXT='yes')
    r = subprocess.run([qemu, elf, 'hi'], capture_output=True, text=True, timeout=60, env=env)
    want = 'argc 2 argv1 hi env yes\natexit ran'
    if r.stdout.strip() != want or r.returncode != 3:
        print('check_xtensa_posix_main: FAIL, got %r exit %d, want %r exit 3'
              % (r.stdout.strip(), r.returncode, want))
        return 1
    pie = os.path.join(tmp, 'c_xt_pmain.pie')
    r = subprocess.run([b + 'ld', '-pie', '--no-dynamic-linker', '-e', 'app_main', '-T',
                        'test/xtensa_pie_prog.ld', obj, '-o', pie], capture_output=True, text=True)
    if r.returncode != 0:
        print('check_xtensa_posix_main: FAIL, PIE link: ' + (r.stderr.strip().splitlines() or ['?'])[0])
        return 1
    lib = os.path.join(tmp, 'c_xt_pmain_lib.o')
    src = os.path.join(tmp, 'c_xt_pmain_lib.c')
    with open(src, 'w') as f:
        f.write('int helper_b(int x) { return x + 2; }\n')
    subprocess.run([cc] + FLAGS + [src, lib], check=True, stdout=subprocess.DEVNULL)
    syms = subprocess.run([b + 'readelf', '-sW', lib], capture_output=True, text=True).stdout
    if not any(l.split()[-1] == 'app_main' and ' WEAK ' in l for l in syms.splitlines() if l.split()):
        print('check_xtensa_posix_main: FAIL, app_main is not WEAK in an object with no main')
        return 1
    rtsrc = os.path.join(tmp, 'c_xt_pmain_rt.c')
    with open(rtsrc, 'w') as f:
        f.write('#include <pxx/runtime_all.h>\n')
    rto = os.path.join(tmp, 'c_xt_pmain_rt.o')
    sho = os.path.join(tmp, 'c_xt_pmain_sh.o')
    she = os.path.join(tmp, 'c_xt_pmain_sh.elf')
    subprocess.run([cc] + FLAGS + [rtsrc, rto], check=True, stdout=subprocess.DEVNULL)
    subprocess.run([cc] + FLAGS + ['--shared-runtime', 'test/c_xtensa_posix_main.c', sho],
                   check=True, stdout=subprocess.DEVNULL)
    subprocess.run([b + 'ld', '-e', 'app_main', '-Ttext=0x10000', sho, rto, '-o', she], check=True)
    r = subprocess.run([qemu, she, 'hi'], capture_output=True, text=True, timeout=60, env=env)
    if r.stdout.strip() != want or r.returncode != 3:
        print('check_xtensa_posix_main: FAIL, --shared-runtime got %r exit %d, want %r exit 3'
              % (r.stdout.strip(), r.returncode, want))
        return 1
    print('check_xtensa_posix_main: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
