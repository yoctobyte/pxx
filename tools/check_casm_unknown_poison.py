#!/usr/bin/env python3
"""x86 inline asm with an instruction pxx's assembler lacks, on x86-64 and i386.

- test/casm_unknown_insn_poison.c: the unknown instruction sits in static
  routines nobody calls (one of them calls the other). gcc never emits
  those, so the file compiles and prints 42.
- Calling such a routine refuses, naming the instruction (the poison).
- In a routine that is not static the compile stops at the instruction, as
  before.
usage: tools/check_casm_unknown_poison.py <compiler> <tmpdir>
bug-c-asm-in-an-unused-static-inline-function-stops-the-compile
"""
import os
import subprocess
import sys

SRC = 'test/casm_unknown_insn_poison.c'
CALLED = ('static inline void bogus(void) { __asm volatile("frobnicate"); }\n'
          'int main(void) { bogus(); return 0; }\n')
EXTERN = ('void bogus(void) { __asm volatile("frobnicate"); }\n'
          'int main(void) { return 0; }\n')


def compile_(cc, target, src, out):
    return subprocess.run([cc, '--target=' + target, src, out],
                          capture_output=True, text=True)


def main():
    cc, tmp = sys.argv[1], sys.argv[2]
    fails = 0
    for target in ('x86_64', 'i386'):
        exe = os.path.join(tmp, 'casm_poison_' + target)
        r = compile_(cc, target, SRC, exe)
        if r.returncode != 0:
            print('casm_poison %s: unused static asm stopped the compile: %s'
                  % (target, (r.stdout + r.stderr).strip().splitlines()[-1:]))
            fails += 1
        else:
            run = [exe] if target == 'x86_64' else ['tools/run_target.sh', 'i386', exe]
            out = subprocess.run(run, capture_output=True, text=True).stdout.strip()
            if out != '42':
                print('casm_poison %s: printed %r, not 42' % (target, out))
                fails += 1
        for name, text, want in (
                ('called', CALLED, 'cannot call bogus: its inline asm uses "frobnicate"'),
                ('extern', EXTERN, 'unsupported instruction: frobnicate')):
            src = os.path.join(tmp, 'casm_poison_%s.c' % name)
            with open(src, 'w') as f:
                f.write(text)
            r = compile_(cc, target, src, os.path.join(tmp, 'casm_poison_%s_%s' % (name, target)))
            msg = r.stdout + r.stderr
            if r.returncode == 0 or want not in msg:
                print('casm_poison %s %s: want a refusal with %r, got rc=%d %r'
                      % (target, name, want, r.returncode, msg.strip()[-200:]))
                fails += 1
    print('casm_poison: %s' % ('FAIL' if fails else 'ok'))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
