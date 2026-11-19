---
track: C
tags: [cfront, wasm32, regression, initialisers, constructors]
prio: 60
type: bug
status: done
owner: claude-dupwt
found-by: pxx2 (bisect), 2026-11-19
blocked-by: []
summary: "On wasm32 every initialised C file-scope variable read 0 (`static int si = 7` printed 0; math.h's NAN, a static const union, read 0.0 so isnan(NAN) was 0), and an __attribute__((constructor)) never ran. Regression from b3c5f711ea, which moved main's initialisers into a hand-emitted __pxx_c_main_init that the wasm backend never builds. Fixed: wasm32 compiles them inline into main again, and constructors are called through AST statements."
---

# C file-scope initialisers read zero on wasm32

## Found

pxx2, fixing the crtl SYS_* guards
(bug-c-crtl-unguarded-syscalls-break-hosted-c-on-wasm32), saw c_wasm32_math_h
still differ from gcc (`isnan(NAN)` 0). `git bisect run` from a7c7ff69b7 (good)
to b5e45aa237 (bad) named b3c5f711ea, which was written by this seat.

## Cause

b3c5f711ea moved main's file-scope initialisers out of main into
CEmitMainInitProc, a procedure built by hand (EmitProcPrologue, then
EmitCallProc from main's head). That keeps main's frame small, which toybox
needs. On wasm32 a body is a wasm function the backend builds from IR, and
neither that hand-built procedure nor the raw call to it ever became one. So
nothing initialised the globals.

Constructors (10a968d88d, later) were called from inside that procedure, so
they had never run on wasm32 at all. A raw EmitCallProc in main's head does not
fix that either. A bare AN_CALL compiled on its own is lowered as a discarded
value, which wasm32 drops. The parser's own `ctor();` works, and the
difference was only the statement wrapper: the call is identical (PXXDBG
a.ast showed the same kind/tk/ival).

## Fix

- wasm32 does not create __pxx_c_main_init. main's head compiles
  CompilePendingGlobalInits and CEmitDeferredCAggInits inline, as before
  b3c5f711ea. wasm32's stack is not main's frame, so the frame-size reason
  does not apply.
- Constructors are compiled there as CCallStmtBlock(proc), a one-statement
  AN_BLOCK/AN_SEQ around the AN_CALL, the shape the parser builds.
- Every other target is unchanged and keeps the out-of-line proc.

## Measured

| | before (HEAD without fix) | after | gcc |
| --- | --- | --- | --- |
| `ctor h` | 0 | 21 | 21 |
| si gi sll gll sd scd sc | all 0 | 7 9 5 6 2.5 3.5 200 | same |

c_wasm32_math_h, c_wasm32_hosted_stdio and c_wasm32_variadic match gcc. x86-64
`g 50 h 3` is unchanged.

Row c_wasm32_fsinit, test/c_wasm32_file_scope_initialisers_and_constructors.c,
compared against gcc's output.
