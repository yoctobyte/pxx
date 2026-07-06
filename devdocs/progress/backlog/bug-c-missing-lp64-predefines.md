# C predefined macros: __LP64__ / _LP64 (and arch predefines) missing

- **Type:** bug (cpreproc), EASY WIN. Track C.
- **Found:** 2026-07-06 c-testsuite run.

## Failing test
- 00212: prints "KO no __*LP*__ defined." — expects `__LP64__`/`_LP64` (x86-64)
  or the ILP32 equivalents per target.

## Fix
cpreproc.inc predefined-macro table: per-target data model macros —
x86-64/aarch64: `__LP64__` `_LP64`; i386/arm32/riscv32/xtensa: `__ILP32__`
(gcc defines it on some 32-bit targets; minimum = LP64 pair on 64-bit).
Check what's already predefined (`__x86_64__` etc.) and align with gcc -dM.

## Gate
Drop 00212.c from test/c-conformance/pxx.skip; runner green.
