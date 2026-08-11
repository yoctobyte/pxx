---
track: A
prio: 45
type: bug
blocked-by: []
status: done
owner: claude-A
---

# A fixed-array function result faults on i386 and arm32

- **Type:** bug (32-bit return ABI) — **Track A**
- **Split from** [[bug-a-set-and-array-function-results-come-back-empty]], which
  made `function F: TArr` work on x86-64, aarch64 and riscv32.

```pascal
type TArr = array[0..2] of Integer;
function MkArr: TArr; begin MkArr[0] := 8; MkArr[1] := 9; MkArr[2] := 10; end;
var a: TArr;
begin a := MkArr; WriteLn(a[0]); end.
```

- **arm32**: SIGSEGV, and it did so on `pinned` too — this shape has never
  worked there.
- **i386**: `pinned` refused it with "arrays not yet supported"; with the path
  wired it compiles and SIGSEGVs.

Both now get a diagnostic instead (`a function result of a FIXED ARRAY type is
not supported on this target yet`), which is the honest state: a refusal beats a
crash, and on i386 it beats a message that named the wrong thing.

## What is already in place

Everything the working targets use is target-neutral and already runs for these
two: `ProcRetFixedArrBytes` (parser), `ABIRetViaHiddenDestProc` (abi.inc), the
right-sized caller scratch, the epilogue copy, and the caller-side copy-out arm.
Both backends' call sites and `EmitAggregateDestStash` were routed through the
oracle predicate at the same time, so the remaining fault is in one of:

- the 32-bit caller not keeping the dest register alive across argument
  marshalling (i386 `ecx`, arm32 `r12` — both are scratch registers the arg
  loop uses), or
- the epilogue's `rep movsb`-equivalent for a byte count that is not a multiple
  of the word size.

Start by dropping the parser refusal and stepping one call under qemu+gdb; the
whole machinery is present, so this is expected to be small.

## Gate

The repro above matching FPC under `qemu-i386` and `qemu-arm`, plus
`test/test_aggregate_function_results.pas` (currently x86-64/aarch64/riscv32).

## Resolution (2026-08-11) — the refusal was STALE, the fault was already gone

Dropped the parser refusal and measured before touching either backend: the
repro, and a wider matrix, are **correct on all five targets today**. Nothing in
the two suspected places (the 32-bit caller's dest register across argument
marshalling; the epilogue copy for a non-word-multiple byte count) needed a
change — later hidden-destination/oracle work fixed both without anyone
re-testing this shape.

Diffed against `fpc -O1`, matching on x86-64 / i386 / arm32 / aarch64 / riscv32:

- `array[0..2] of Integer` result, with and without arguments
- `array[0..2] of Byte` and `array[0..4] of Byte` — 3 and 5 bytes, i.e. exactly
  the non-word-multiple copy the ticket suspected
- `array[0..1] of Int64`, and a 2-D `array[0..1,0..1] of Integer`
- a six-argument function returning an array, and one whose arguments are
  themselves calls (the scratch-register concern: i386 `ecx`, arm32 `r12`)
- `test/test_aggregate_function_results.pas` — byte-identical output on
  x86-64, i386 and arm32

Two adjacent gaps surfaced while building the matrix; both are separate refusals
with honest diagnostics, neither is this bug:

- `SumA(MkArr)` — a fixed-array call result as a `const` by-ref argument is
  refused, where the record and string arms already materialise a temp. Filed as
  `bug-a-a-fixed-array-call-result-is-refused-as-a-const-byref-argument`.
- `MkArr(4,5,6)[2]` — indexing a call result directly; already tracked by
  `feature-a-index-an-array-returning-call-directly`.

## Log
- 2026-08-11 — resolved, commit 4048fe238.
