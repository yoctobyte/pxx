---
track: ESP
tags: [C, xtensa, setjmp, crtl, busybox]
prio: 20
type: feature
blocked-by: []
summary: "C setjmp/longjmp exist on xtensa, call0 and windowed. EmitCSetjmpStubs had no xtensa arm and both call sites skipped xtensa, so <setjmp.h> could not be used at all: setjmp.c's longjmp referenced __pxx_longjmp, which nothing defined, and the xtensa runtime object (runtime_all.h) did not build. Windowed uses the design of the Pascal exception helpers (spill every window with a CALL8 chain, save and restore the caller's two save areas, forge a0/a1, RETW). Call0 saves a0, sp and a12..a15. longjmp delivers val, with 0 becoming 1."
status: done
owner: unassigned
---

# C setjmp/longjmp on xtensa

pxx2 found it while building the xtensa runtime object for BusyBox: `#include <pxx/runtime_all.h>` stopped at "__pxx_longjmp is a pxx-internal runtime symbol and cannot be imported dynamically".

## Windowed
This is exception_emit.inc's ExcSetJmp/ExcLongJmp design; its comment explains why no privileged instruction and no spill syscall is used. The C version differs in three ways:
- Each body carries its own spill chain, so no call crosses procs and DCE can move each body independently.
- longjmp takes val in a3.
- The buffer uses 11 of jmp_buf's 32 words.

## Call0
setjmp saves a0, sp and the callee-saved a12..a15.

## Test
tools/check_xtensa_setjmp.py runs test/c_xtensa_setjmp.c against gcc's output in c_xtensa_setjmp.expected:
- a longjmp from 12 frames down
- val 0 arriving as 1
- three jumps to one buffer
- a second buffer used inside a callee
- volatile locals kept across the jumps

It runs call0 as a hosted program and windowed as an object through the posix process entry. Both matched gcc first time. The old compiler can't compile the test.
