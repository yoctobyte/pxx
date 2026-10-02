---
type: perf
track: A
prio: 45
status: open
slug: perf-a-a-routine-with-a-managed-result-pays-an-exception-frame-even-when-its-body-cannot-raise
summary: "Every routine with a managed result or managed locals installs an unwind cleanup frame on every call: zero-init, a setjmp-style register save, push and pop of the thread's handler chain, and a copy-out. This happens whether or not the body can raise. pylib's `pynone` is four stores and costs ~76 instructions per call. Nil Python iteration goes through dozens of these per element: list(range(32)) costs ~78k instructions, 25 us against CPython's under 1 us. Fix: decide the frame AFTER the body is known, and skip it when the body makes no call and has no raise."
---

# A routine with a managed result pays an exception frame even when its body cannot raise

## Measured (2026-10-02, frankuser, x86-64, default -O)

`def f(n): for i in range(n): x = list(range(32))`, 2000 passes, run under
callgrind. Symbols come from the program's .map, which lists about 480 of
its 2300 procs, so unlisted addresses resolve to the nearest listed one.

- 156.6M instructions in total, ~78k per `list(range(32))`, ~2.4k per element.
  That is after the pyiter_has split (below); before it, the total was 236M.
- `pynone` (pylib.pas: two stores into `Result`) costs ~76 instructions per
  call. The disassembly shows a 16-byte `rep stos` zero-init, a call into the
  frame-enter helper, a `%gs:0x40` handler-chain push and pop, and a 16-byte
  `rep movsb` copy-out. The body itself is four instructions.
- PXXVarClear, PXXVarReleasePayload, PyVarSlotClear and PyVarSlotSet together
  are about a third of the profile, mostly the box put/take and the result
  copies on every step.

## Where the decision is made

`pasparser_proc.inc`, about line 3735:

    needsProcCleanupFrame := TargetHasProcCleanupFrame and ExceptionUsed and
                             (not isAsmFunc) and ProcHasManagedLocalCleanup(procIdx, -1);

The decision is made at the PROLOGUE, before the body is parsed, so the
compiler cannot yet know whether the body can raise. The late-arm path
(`ProcCleanupFrameWanted` / `ProcCleanupFrameLateArmed`, about line 3970) shows
a frame can be decided after the body has been compiled. This ticket wants the
reverse: request a frame at the prologue, then cancel it.

## Shape of a fix

The frame exists to release managed locals when an exception unwinds through
the routine. A body that makes no call, has no `raise`, and has no
checked operation that traps into the exception runtime cannot be unwound
through, so it does not need the frame. Two options:

1. Patch the frame-enter sequence to a jump over itself once the body is
   compiled and shown to be leaf and non-raising, on each backend that has
   `EmitProcCleanupFrameEnterForTarget`.
2. Defer prologue emission until after ParseBlockAST. This is cleaner but
   touches every backend's prologue order.

`pynone` is the tiny case. The bigger win is RTL routines that call only
other non-raising RTL routines. Covering those needs a per-proc "cannot raise"
bit propagated bottom-up, which is a larger job.

## Related, landed with this ticket

`pyiter_has` minted about 46 Variant temps across all its arms and cleared
them all on every call (2.97M clears in this profile). It now has a fast path
with no managed temps for list, range and generator cursors. The rest go to
`pyiter_has_slow`. Same program: 236M → 157M instructions, and the per-call
times in the format/set leak fixture halved for the range rows.
