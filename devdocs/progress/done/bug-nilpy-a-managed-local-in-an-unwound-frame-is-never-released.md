---
track: N
prio: 55
type: bug
blocked-by: []
status: done
owner: frankb-78
summary: "FIXED 2026-09-04. No Nil-Python function ever got an unwind landing pad, so every managed local live in a frame an exception unwound PAST leaked one heap block per raise, unbounded. The pad machinery is shared and was complete; `ProcCleanupFrameWanted := True` was simply written in exactly one file, pasparser_proc.inc. Measured slope of live blocks per raise: 0.900 for one string local, 1.854 for two, 3.022 for three, 1.897 for a list (object + buffer), 0.000 with no managed local and 0.000 when the frame is not unwound. Fixed by arming the shared late gate in PyParseDef and PyParseMethod. Pascal was flat on all seven rows throughout."
---

# A Nil Python managed local in an unwound frame is never released

## What was measured

`-dPXX_ALLOC_CENSUS`, slope of `live` between N=2000 and N=8000 raises, one
binary (`ca07aca86948`, commit `999c76dc6`):

| probe | per raise |
| --- | --- |
| `raise` inline in the loop, dynamic message | 0.000 |
| `raise` in a callee holding NO managed local | 0.000 |
| callee, 1 string local, CONSTANT message | 0.900 |
| callee, 2 string locals | 1.854 |
| callee, 3 string locals | 3.022 |
| callee, 1 list local | 1.897 |
| callee, 1 string local, NO raise | 0.000 |

One block per managed heap object live in the unwound frame. The 0.9/1.85/3.02
rather than 1/2/3 is the census's geometric threshold, not a partial leak — the
last line it prints is ~0.94 of the true total, and the RATIOS are 1 : 2 : 3.

**The first two rows are what name the trigger.** Row 3 raises a CONSTANT
message and still leaks, so it is not "the message was built in this frame";
row 2 has a callee and a raise and does not leak, so it is not the exception
object. It is what the frame HOLDS at raise time, and only when the frame is
unwound past.

The Pascal equivalent of every row is flat, which is what pointed at the cause.

## The cause

A proc that can be unwound past needs a landing pad or its managed locals are
never released: neither its own epilogue nor the eventual handler's frame runs.
The machinery for that is entirely shared and was entirely complete —
`ProcCleanupFrameWanted` / `ProcCleanupFrameLateArmed` in `defs.inc`, the late
gate inside `CompileAST` (`ir_codegen.inc`), `EmitProcCleanupLandingPadForTarget`
next to it, six backends' `IR_EXC_ENTER` behind `TargetHasProcCleanupFrame`.

`grep -rn 'ProcCleanupFrameWanted := True' compiler/` returned two hits, both in
`pasparser_proc.inc`. Nothing else in the compiler ever asked for a pad, so no
`.npy` def, method, lambda or comprehension body has ever had one.

**This is the shape [[the-substrate-is-ast-and-ir-not-the-parser]] predicts and
the shape [[ir-as-substrate]] is meant to prevent**: the capability lives in the
substrate, the REQUEST for it lives per-frontend, and a frontend that never
learned to ask is silently without it. Nothing errors — an unwind leak prints
nothing and corrupts nothing.

## The fix

`PyArmCleanupFrame` / `PyTakeCleanupPad` in `pyparser.inc`, called at the two
body sites (`PyParseDef`, `PyParseMethod`). Only the LATE gate is used: the
Pascal frontend also asks an early one from the prologue, and that one is
structurally unable to see the hidden temps lowering mints, so the late gate is
a superset of it. `ProcExceptionCleanupFrameActive` is stacked, because a nested
def is drained by re-entering `PyParseDef`.

The C, Rust and Zig frontends have the same gap by the same grep. Not measured
here and not claimed — filed as
[[bug-a-only-the-pascal-frontend-ever-asks-for-an-unwind-landing-pad]].

## The guard

`test/test_nilpy_managed_local_in_unwound_frame.npy`, wired in `test-nilpy` with
BOTH `expect_same` and `assert_no_leak`, because only one of them can fail:

| | pin v403 (pre-fix) | HEAD |
| --- | --- | --- |
| printed output | `total=66890` / `msg=fixed` | identical |
| census `live` at 102900 allocs | **18509** | **4** |

An `expect_same` row alone certifies the leak as correct. The value row still
earns its second: the pad releases and then RE-RAISES, so `msg=fixed` is what
says the re-raise still carries the original exception.

## Not this

- [[bug-nilpy-except-x-as-e-still-leaks-every-exception-the-bare-arm-fix-did-not-cover-it]]
  — the exception OBJECT, on a path that is not unwound past a frame. Still open;
  this fix does not touch it.
- [[bug-nilpy-a-generator-instance-leaks-its-locals-and-argument-cells]] — one-off
  per generator instance, present with or without an exception.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 4edf60ff9.

## Targets

The pad now emits on all six register backends for `.npy` bodies
(`TargetHasProcCleanupFrame`: x86-64, i386, arm32, aarch64, riscv32, xtensa).

Measured on every target where a `.npy` program builds at all, control from pin
v403 on the same source:

| target | pin v403 `live` | HEAD `live` | allocs |
| --- | --- | --- | --- |
| x86-64 | 18509 | 4 | 102900 |
| i386 | 27146 | 7 | 115763 |
| aarch64 | 18509 | 4 | 102900 |
| arm32 | 18509 | 4 | 102900 |

All four print `total=66890 / msg=fixed` on both binaries. The three cross rows
are wired in `test-i386`, `test-aarch64` and `test-arm32` next to the existing
`.npy` census rows.

riscv32 and xtensa do not build a `.npy` program at all, on the pin AND at HEAD:
`a heap arena needs mmap, which this profile has not`, already filed as
[[bug-a-nilpy-on-cross-targets-four-remaining-walls]]. So the pad emits there
and is unexercised — an absence, said out loud rather than left as a gap in the
table.

**wasm32 is a no-op and was never affected.** That predicate means "goes through
the PARSE-TIME hook", not "has no cleanup frame" — `ir_codegen_wasm32.inc:6611`
asks `ExceptionUsed and ProcHasManagedLocalCleanup(...)` itself at codegen,
frontend-agnostically, so NilPy on wasm32 already had a pad. Reading the
predicate the other way would have been the expensive kind of wrong, and its
own comment says so.

There is no wasm32 row for the test regardless: it fails to compile for that
target on the pin AND at HEAD, identically — `undefined variable (SYS_openat)`
in `lib/rtl/platform/posix/platform_backend.pas`. That has an owner and a design
fork of its own, filed by frankA the same night:
[[bug-n-the-nilpy-pal-issues-raw-syscalls-so-every-file-body-traps-on-wasm32]]
(`compiler/builtin/pypal.pas` carries no wasm/wasi conditional at all, while
`lib/rtl/platform/wasi` exists and the Pascal RTL uses it). The wasm32 row for
this test becomes available when that closes, not before.

**And the thing that made me suspect a stale ticket was my own misreading.**
I flagged `bug-a-managed-locals-leak-on-an-unwind-on-wasm32-and-xtensa` as
looking stale on both halves of its title. It is in `done/` and has been: wasm32
got its frame in `83018bb5e`, xtensa's half in `af5d2b534`. **A done ticket
keeps the title of the BUG, never of the current state** — that title is a
correct description of what was wrong and stays so forever, and reading it as a
claim about HEAD is the same error as reading `working/` as a lock. Locate a
ticket's FOLDER before flagging its title; the summary opens with `DONE (sha)`
and says the rest.
