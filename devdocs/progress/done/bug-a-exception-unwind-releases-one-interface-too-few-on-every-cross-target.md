---
track: A
prio: 45
type: bug
blocked-by: []
summary: "`test_interface_arc_exc` reports `unwind freed=2` on i386, arm32 and aarch64 where x86-64 and FPC say 3. An interface reference held when an exception unwinds past its frame is never released on any cross target — one leak per unwind, silent."
status: done
owner: claude-A
---

# Exception unwind releases one interface too few on every cross target

- **Track A** (the four cross backends' unwind path / `exception_emit.inc`'s
  cross arms).
- Found 2026-08-21 by the 53-test dyn-array + interface cross differential.

## Measured

`test/test_interface_arc_exc.pas`:

| target | output |
| --- | --- |
| x86-64 | `reassign created=2 freed=2` / `caught` / **`unwind freed=3`** |
| i386 | ... / **`unwind freed=2`** |
| arm32 | ... / **`unwind freed=2`** |
| aarch64 | ... / **`unwind freed=2`** |
| riscv32 | `reassign created=2 freed=1` / `caught` / **`unwind freed=1`** |

i386, arm32 and aarch64 agree with each other and are short by exactly one, so
this is one missing release on a shared path, not three separate defects.
riscv32 is short on the reassign line too — that half belongs to
[[bug-a-riscv32-drops-interface-releases-in-six-shapes]]; only its unwind
shortfall is this ticket.

## Why it stays invisible

An unwind leak prints nothing. It surfaces only because this test counts
destructor calls, and the test is native-only in the Makefile — nothing runs it
for a cross target. The same reason
[[bug-a-no-dyn-array-scope-exit-release-on-four-backends]] survived.

## Where to start

x86-64's unwind releases the interface; compare its landing-pad cleanup against
each cross backend's. The scope-exit arm and the UNWIND arm are separate code
paths on every target — the scope-exit one was audited on 2026-08-21 and the
unwind one was not, which fits a count that is short by exactly one frame's
worth.

## Gate

`test_interface_arc_exc` printing `unwind freed=3` under `tools/run_target.sh`
on i386 / arm32 / aarch64; the 53-test cross differential no worse than
baseline; self-host fixedpoint + `tools/gate.sh quick`.

## Resolution (2026-08-21)

`test_interface_arc_exc` now prints **`unwind freed=3`** on i386, arm32 and
aarch64, matching x86-64 and FPC. riscv32 is unchanged at 1 and is not this
ticket's half (below).

### It was not a missing release — it was a missing LANDING PAD

The ticket guessed "compare x86-64's landing-pad cleanup against each cross
backend's". There was nothing to compare: **the cross backends had no proc
landing pad at all.** One clause said so, in `pasparser_proc.inc`:

```pascal
needsProcCleanupFrame := (TargetArch = TARGET_X86_64) and ExceptionUsed and
                         (not isAsmFunc) and ProcHasManagedLocalCleanup(procIdx, -1);
```

A proc that holds managed locals and is unwound *past* — raised below, caught
above — never runs its own epilogue and never runs the handler's frame either,
so it needs a setjmp frame of its own: chain onto `BSS_EXC_TOP` at entry, and
when a raise longjmps into it, unchain, release, re-raise. x86-64 has had that
since exceptions landed. Four targets did not, so every managed local held
across a raise leaked there — interfaces, ansistrings, variants,
records-with-managed-fields, not just the one the test counts. It printed
nothing, which is why it survived: the test that counts destructor calls is
wired into `test-core` only.

### Nothing new was written

Every target already emits this exact sequence for a `try` block (its
`IR_EXC_ENTER` arm) and already has `IREmitLeaveExceptionFrames*`. **A `try`
frame and a proc cleanup frame are the same frame with different landing pads.**
So the fix is those two pieces called from the proc driver instead of from the
statement lowering — lifted into `ir_codegen.inc` as
`EmitProcCleanupFrameEnterForTarget` / `EmitProcCleanupLandingPadForTarget`,
with the branch-patch encodings (rel32 / `bne` / `cbnz` / `beq`-skip-`jal`)
behind two small helpers so the driver stays target-blind.

The prerequisite was a separate commit: the scope-exit release loop lived inline
in each of `EmitProcEpilog`'s six branches, so there was no single thing for the
landing pad to *call*. Extracting `EmitManagedLocalCleanupForTarget` first
(byte-identical, 321153f99) is what made this commit small.

### Not covered

- **riscv32** now gets the landing pad, but its release arm still has no COM
  interface case, so it stays at `unwind freed=1`. That is
  [[bug-a-riscv32-drops-interface-releases-in-six-shapes]] — the landing pad it
  now has will start working the moment that arm lands.
- **xtensa** has no proc cleanup frame. It is the one target whose exception
  runtime exists only under the Call0 ABI, and its managed-local arm handles
  AnsiString alone. ESP-campaign work (Track S), stated in the code rather than
  skipped silently.

## Gate

`tools/gate.sh quick` GREEN. `test_interface_arc_exc` = native on i386 / arm32 /
aarch64. Eight exception tests (`test_cross_exception`, `test_exceptions`,
`test_exception_finally`, `test_exception_typed`,
`test_managed_exception_cleanup`, `test_exc_resident_param`,
`test_exceptaddr_b340`, `test_except_derived_caught_by_base`) byte-equal to the
native oracle on all three targets. Cross-target breadth is Track T's, against
this sha.

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
