---
summary: "`Copy(a, 1, 2)[0]` is `unexpected token` while `Length(Copy(a, 1, 10))` works — the dynamic-array Copy intrinsic Exits past the postfix chain"
type: bug
track: P
prio: 45
status: done
---

# The result of a dynamic-array `Copy` cannot be indexed

- **Type:** bug (Pascal frontend) — Track P
- **Opened:** 2026-08-27
- **Found by:** `tools/fpc_diff_probe.sh`, row `dynarray-copy-and-alias`. The row
  had been tagged `known` since it was written with **no ticket behind it** —
  the probe's own header calls that "a lie with a cost". This is the ticket.

## Repro

```pascal
var a: array of Integer;
begin
  SetLength(a, 3); a[0] := 1; a[1] := 2; a[2] := 3;
  writeln(Length(Copy(a, 1, 10)), '|', Copy(a, 1, 2)[0]);
end.
```

FPC prints `2|2`. pxx:

```
Expected: ), but got: [ (Kind: 76)
error: unexpected token
```

`Length(Copy(...))` works, `Copy(...)[i]` does not — the two disagree about the
same value, which is the tell.

## Cause

The dynamic-array arm of the `Copy` intrinsic (`pasparser_expr.inc`) builds an
`AN_DYN_COPY` node, sets `CurASTNode` and `Exit`s. Nothing consumes a postfix
suffix, so the trailing `[` is left for the statement parser and reported at the
wrong place. The STRING arm of the same intrinsic does not have this problem: it
hands its `AN_CALL` to `ApplyCallResultPtrSuffix`, which walks the chain
(`compat-pascal-index-a-function-call-result` did that half).

The reason the dyn arm could not do the same is that `ApplyCallResultPtrSuffix`
is keyed on a **procIdx** and reads six `ProcRet*` fields — and an `AN_DYN_COPY`
is not a call and has no proc row. That is the same procIdx-vs-node coupling
[[bug-p-a-record-cast-as-an-assignment-target-cannot-be-indexed]] runs into from
the other side.

## Shape of the fix

Not "add a suffix loop to the Copy arm" — that would be the second copy of a
walk that already exists. The dyn-array half of `ApplyCallResultPtrSuffix`
(materialise the handle into a hidden dyn-array temp, index the temp, keep
taking brackets while levels remain, then let a record element's `.field` tail
run) is already self-contained; it only needs its four shape facts —
element kind, element rec, `array of` depth, and the rec a record tail resolves
against — as ARGUMENTS instead of as `ProcRet*` lookups. The Copy arm then reads
them off the source node with `NodeDynBaseTk` / `NodeDynBaseRec` /
`NodeDynDepth`, which is the very trio `AN_DYN_COPY`'s own lowering uses.

## Gate

The probe row matches FPC and is untagged; a test covering an Integer element, a
RECORD element (so the `.field` tail runs), a managed STRING element, the
one-argument `Copy(a)` shorthand indexed directly, and the temp's lifetime under
a loop; `tools/gate.sh quick` + self-host fixedpoint.

## Outcome (2026-08-27)

Fixed as sketched, in the same sitting the ticket was written — the ticket
exists because the probe row was tagged `known` with nothing behind it, so it is
filed and closed together.

`IndexDynArrayValue(node, elemTk, elemRec, dynDepth, tailRec; var outTk)` in
`pasparser_lval.inc` is the dyn-array half of `ApplyCallResultPtrSuffix`, lifted
out verbatim and keyed on the NODE's element shape instead of a proc row. Both
callers now go through it: the array-returning CALL path passes its `ProcRet*`
fields, and the `Copy` intrinsic passes `NodeDynBaseTk` / `NodeDynBaseRec` /
`NodeDynDepth` of the SOURCE array — the same trio `AN_DYN_COPY`'s lowering
reads, so the temp and the copy cannot disagree about the element.

One materialisation point, one lifetime story. The lifetime was re-measured on
the new path: 200k iterations of `acc := acc + Copy(a, 1, 2)[0]` hold RSS flat
at 392kB, and that loop is row e of the test.

Test: `test/test_dynarray_copy_result_indexed.pas` (Integer element, record
element with a `.field` tail, managed string element, the `Copy(a)` shorthand
indexed directly, and the loop). Probe row `dynarray-copy-and-alias` untagged.

Gate: quick GREEN, self-host fixedpoint byte-identical.

## Log
- 2026-08-27 — resolved, commit 009b8af3c.
