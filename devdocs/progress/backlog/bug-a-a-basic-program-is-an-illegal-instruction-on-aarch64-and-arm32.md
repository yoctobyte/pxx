---
track: A
prio: 30
type: bug
summary: "Every .bas program compiled for aarch64 or arm32 dies with SIGILL at startup — on HEAD and on `pinned` alike. The BASIC jobs are native-only in the matrix, so nothing was watching."
---

# A BASIC program is an illegal instruction on aarch64 and arm32

- **Type:** bug (Track A — the BASIC driver's target-conditional emission)
- **Status:** backlog — opened 2026-08-24, found in passing while fixing
  [[regression-test-core-test-basic-comprehensive-2]]
- **Owner:** —

## Repro

```
compiler/pascal26 --target=aarch64 test/test_basic_comprehensive.bas /tmp/b64
qemu-aarch64 /tmp/b64
  qemu: uncaught target signal 4 (Illegal instruction) - core dumped
```

Same for `--target=arm32` under `qemu-arm`. Both COMPILE cleanly and die at
runtime, before the first line of output. `--target=i386` is fine (21 lines,
correct). x86-64 is fine.

**Not a regression:** `stable_linux_amd64/default/pinned` produces the same
SIGILL on both targets. This is how BASIC cross-compilation has always been.

## Why nothing caught it

The `.bas` jobs run in the **native** tier only — `tstate` shows
`job_tier/test-core#src:test/test_basic_comprehensive.bas = native` — so no
cross-target verdict has ever been published for this frontend. The failure is
old, silent and complete.

## Where to look first

The BASIC driver open-codes its program prologue, and its entry stub is emitted
as raw x86-64 bytes in at least one place (`EmitB($E9)` + a 32-bit displacement
patch) rather than through `EmitProgramEntryForTarget`, which is the routine
that exists precisely because "every other frontend open-coded the x86-64 one
and nothing else, and a NilPy arm32 binary began with x86-64 bytes" — that
comment is in `pasparser_prog.inc` today, describing the identical bug in a
different frontend.

So the likely shape is: the ELF entry point of a `.bas` binary on aarch64/arm32
contains x86-64 instruction bytes. Check that before anything else — decode the
first bytes at the entry point and compare with a Pascal binary for the same
target.

This is one more instance of the checklist-in-five-copies problem;
[[refactor-a-one-program-driver-prologue-for-every-frontend]] is the systematic
fix, and would likely close this ticket as a side effect.

## Gate

`.bas` tests pass under qemu on aarch64 and arm32, native and i386 unchanged,
self-host byte-identical.
