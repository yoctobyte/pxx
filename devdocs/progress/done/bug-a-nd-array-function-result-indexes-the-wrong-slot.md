---
track: A
prio: 50
type: bug
blocked-by: []
status: done
owner: claude-A
---

# An N-D array function RESULT indexes the wrong slot inside the callee

- **Type:** bug (silent wrong value) — **Track A**
- **Found:** 2026-08-09, while making 1-D fixed-array results work
  ([[bug-a-set-and-array-function-results-come-back-empty]]).
- **Pre-existing:** identical on `pinned`.

```pascal
type TArr2 = array[0..1, 0..1] of Integer;
function MkArr2: TArr2;
begin
  MkArr2[0,0] := 1; MkArr2[0,1] := 2; MkArr2[1,0] := 3; MkArr2[1,1] := 4;
  WriteLn('inside ', MkArr2[0,0], ' ', MkArr2[0,1], ' ', MkArr2[1,0], ' ', MkArr2[1,1]);
end;
```

FPC prints `inside 1 2 3 4`. pxx prints **`inside 1 3 3 4`** — before any return
happens, so this is not a return-ABI problem: writing `MkArr2[0,1]` lands in the
wrong slot. The read-back of `[0,1]` then answers `[1,0]`'s value.

That is why an N-D array result is now REFUSED at the declaration rather than
returned: delivering it correctly would only hand the caller the callee's own
garbage faithfully.

## Where to look

The Result symbol of an array-returning function is allocated by the
`AllocVar('Result', retType)` path with the array shape stamped from
`LastType*`, not by `AllocArray`. A 1-D result indexes correctly, so the
per-dimension stride (`SymArrNDims` / the dim spans) is the suspect — most
likely never stamped on the Result symbol, leaving the N-D index lowering to
compute with a missing or default row length.

Compare against an ordinary N-D LOCAL, which indexes correctly, and diff what
the two symbols carry.

## Gate

The repro matching FPC, then remove the parser refusal added with the 1-D work
and extend `test/test_aggregate_function_results.pas` with the 2-D rows it
currently omits.

## Resolution (2026-08-10)

The ticket named the N-D strides. That was one of THREE symptoms of a single
missing stamp, and the N-D one was not even the worst.

`AllocVar('Result', retType)` allocated the fixed-array Result as **one scalar
of the element type** — `IsArray := False`, `ArrLen := 0`, `SymArrNDims := 0`,
and `TypeSize(elemKind)` bytes of frame. So:

1. **1-D overran the frame.** `array[0..2]` survived on frame padding, which is
   why the shipped test only ever spelled it that way. `array[0..3]` wrote index
   3 over the saved return address: SIGSEGV on `pinned`, at HEAD, and from a
   plain `a := MkArr` in the main body. Not filed anywhere — the existing test's
   one row was three elements long.
2. **N-D had no dim spans**, so `MkArr2[0,1] := 2` linearised against a missing
   stride: `1 2 3 4` read back as `1 3 3 4`. The reported symptom.
3. **The element KIND was wrong for every non-Integer element.** An array-type
   alias is not in the scalar alias table, so `ParseTypeKind` fell through its
   unknown-name default and answered `tyInteger` — right by accident for
   `array of Integer`, an Integer-strided Result for `array[0..2] of string[8]`
   (came back blank) and `array[0..1,0..1] of TRec` (`1 2 3 4` -> `2 4247906 0 0`).
   Also pre-existing on `pinned`, in the 1-D case, unfiled.

Fix: allocate the Result with `AllocArray` over the alias's flattened bounds and
stamp `SymArrNDims`/`SymArrDimLo`/`SymArrDimSpan` from the ArrType entry — the
same thing `ParseVarSection` does for a variable of the alias — take the element
kind from `ArrTypeElemTk` instead of `ParseTypeKind`, and restate
`ProcRetFixedArrBytes` from the element's real SLOT size (`RecSize` /
`FrozenStrSlotSize`, the elemSize rule ir.inc already uses for a whole-array
copy) rather than `TypeSize`.

One sibling fell out of it: **`ArrTypeElemStrCap` is new.** Nothing recorded a
frozen-string element's width on the array TYPE, so both the var path and this
one read `LastTypeStrCap` — whatever the last unrelated `string[N]` anywhere in
the unit happened to leave behind. It worked for a var only because the alias's
own declaration is usually the most recent one. Now carried on the ArrType entry
and consumed at both use sites.

The parser refusal for N-D results is gone. The i386/arm32 refusal stays — that
is `bug-a-fixed-array-function-result-faults-on-i386-and-arm32`, still open.

## Verified

All rows diffed against `fpc -O1` (`{$mode objfpc}`):

- 1-D (4 elements, with a guard local), 2-D, 3-D with non-zero lo bounds
  (`array[1..2, 0..2, 5..6]`), array-of-`string[8]`, N-D array-of-record.
- Every spelling of the declaration: bare function, `forward` + implementation,
  instance method, `class function`, and `Result[...]` vs the function-name form.
- Cross: x86-64, aarch64, riscv32 all match FPC. i386/arm32 still refuse.
- `test/test_aggregate_function_results.pas` extended with all of the above and
  its Makefile assertions added.
- Family sweep, HEAD vs `pinned`, over all 824 `test/*.pas`: no behavioural
  difference except this test (which `pinned` now refuses to compile). The 191
  array/string/record tests were swept first and were identical.
- `tools/gate.sh quick` GREEN; self-host fixedpoint converged in 1 round.

Not fixed, found in passing and NOT part of this ticket: subscripting a call
result directly (`MkR[1,1].b`) is a parse error. Pre-existing.

## Log
- 2026-08-10 — resolved, commit 5f8e1ccce.
