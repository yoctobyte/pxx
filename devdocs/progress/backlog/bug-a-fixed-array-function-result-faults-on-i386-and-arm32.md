---
track: A
prio: 45
type: bug
blocked-by: []
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
