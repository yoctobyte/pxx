#!/usr/bin/env python3
"""--freestanding x86-64 (kernel code): VLA/alloca work without the red zone,
and float/double arithmetic is refused.

1. test/c_freestanding_vla.c as a --freestanding object, linked with gcc and
   run: it prints what the gcc-built object prints, and none of its own
   functions (vla, mid, check) touches memory below rsp.
2. Float arithmetic in --freestanding C is refused (it needs the SSE
   registers; gcc -mgeneral-regs-only), while loads/copies of a double, a
   struct with a double field and the VLA file compile.
usage: tools/check_freestanding_vla_sse.py <compiler> <tmpdir>
feature-c-freestanding-vla-frame-slots-and-sse-refusal
"""
import os
import re
import subprocess
import sys

SRC = 'test/c_freestanding_vla.c'
MAIN = '#include <stdio.h>\nlong check(void);\nint main(void){printf("%ld\\n", check()); return 0;}\n'
REFUSED = ['double add(double a, double b) { return a + b; }',
           'int lt(double a, double b) { return a < b; }',
           'long d2i(double x) { return (long)x; }',
           'long half(long x) { double d = x; return (long)(d / 2); }']
ACCEPTED = ['void cp(double *a, double *b) { *a = *b; }',
            'struct s { double d; long x; }; long get(struct s *p) { return p->x; }']


def sh(*a, **k):
    return subprocess.run(list(a), capture_output=True, text=True, **k)


def main():
    cc, tmp = sys.argv[1], sys.argv[2]
    fails = []
    m = os.path.join(tmp, 'fsvla_main.c')
    with open(m, 'w') as f:
        f.write(MAIN)
    po, go = os.path.join(tmp, 'fsvla_p.o'), os.path.join(tmp, 'fsvla_g.o')
    r = sh(cc, '--freestanding', '--emit-obj', SRC, po)
    if r.returncode:
        fails.append('pxx refused %s: %s' % (SRC, (r.stdout + r.stderr).strip()[-200:]))
    else:
        sh('gcc', '-O0', '-c', SRC, '-o', go, check=True)
        outs = []
        for o, x in ((po, 'fsvla_p'), (go, 'fsvla_g')):
            exe = os.path.join(tmp, x)
            sh('gcc', '-no-pie', m, o, '-o', exe, check=True)
            outs.append(sh(exe).stdout.strip())
        if outs[0] != outs[1] or not outs[1]:
            fails.append('VLA object printed %r, gcc %r' % tuple(outs))
        for fn in ('vla', 'mid', 'check'):
            dis = sh('objdump', '-d', '-M', 'intel', '--disassemble=' + fn, po).stdout
            if '<%s>:' % fn not in dis:
                fails.append('no function %s in the object' % fn)
            bad = [l.strip() for l in dis.splitlines() if re.search(r'\[rsp-0x', l)]
            if bad:
                fails.append('%s touches memory below rsp: %s' % (fn, bad[0]))
    for want_ok, cases in ((False, REFUSED), (True, ACCEPTED)):
        for i, text in enumerate(cases):
            src = os.path.join(tmp, 'fsvla_%s%d.c' % ('ok' if want_ok else 'fp', i))
            with open(src, 'w') as f:
                f.write(text + '\n')
            r = sh(cc, '--freestanding', '--emit-obj', src, src + '.o')
            msg = r.stdout + r.stderr
            if want_ok and r.returncode:
                fails.append('refused, should compile: %s: %s' % (text, msg.strip()[-160:]))
            if not want_ok and (r.returncode == 0 or 'float/double arithmetic is not supported' not in msg):
                fails.append('not refused: %s (rc=%d)' % (text, r.returncode))
    for f in fails:
        print('check_freestanding_vla_sse: ' + f)
    print('check_freestanding_vla_sse: %s' % ('FAIL' if fails else 'ok'))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
