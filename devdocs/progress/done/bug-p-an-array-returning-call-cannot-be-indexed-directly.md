---
slug: bug-p-an-array-returning-call-cannot-be-indexed-directly
title: "`f(x)[i]` — indexing the result of an array-returning function is refused"
track: P
prio: 30
type: bug
blocked-by: []
status: done
owner: ""
created: 2026-08-25
summary: "`MakeDyn(3)[2]` fails with `cannot index the result of an array-returning function directly — assign it to a variable first`. fpc 3.2.2 compiles and runs it. `Length(MakeDyn(3))` on the same call already works, so the call result IS materialised somewhere the intrinsic can reach; only the subscript path declines it."
---

# Repro

```pascal
program idx;
type TDyn = array of Integer;
function MakeDyn(k: Integer): TDyn;
var z: Integer;
begin
  SetLength(Result, k);
  for z := 0 to k - 1 do Result[z] := z;
end;
begin
  WriteLn(Length(MakeDyn(3)));   { 3 — works }
  WriteLn(MakeDyn(3)[2]);        { fpc: 2 — pxx: refused }
end.
```

```
pascal26: error: cannot index the result of an array-returning function directly
                 — assign it to a variable first
```

The diagnostic is honest and pre-existing (it is not the
bug-p-ten-constructs work), but it is a refusal of valid Pascal, and the sibling
construct on the very next line proves the value is available: `Length` of the
same call already answers correctly, which means the result is materialised in a
temporary the intrinsic can measure. The subscript path needs the same
temporary — the "lifted temp is an addressable record" move
ParseClassRecordSelectors already makes for a record-returning call
(`feature-pascal-record-constructors`) is the shape to copy.

Same family as the already-fixed
`bug-p-a-call-result-is-refused-as-a-const-open-array-argument`: a call RESULT is
a first-class array value everywhere except the one path that never learned to
lift it.


## RESOLVED 2026-08-25 — already fixed; this was a re-filing of the same gap

The repro on this page now prints `3` / `2`, matching fpc.

Fixed by `dd35abca2` under
[[compat-pascal-index-a-function-call-result]], whose seven-row table this is
one row of — and by the shape this ticket itself proposed: one materialisation
point (`ApplyCallResultPtrSuffix`) lifts the call result into a hidden
dyn-array local, and `tmp[i]` is then the ordinary variable index. No IR change
was needed; the whole gap was that a call node has no SYMBOL for the index path
to key on.

`3fba47f2b` closed the two rows still open after that (`High(f)` and
`for x in f`). The regression test is
`test/test_index_a_dynamic_array_call_result.pas`, whose `.expected` is fpc
3.2.2's own output.

Closed as a duplicate rather than worked: it was filed independently on
2026-08-25 by a probe sweep, on the same day the fix landed.

## Log
- 2026-08-25 — resolved, commit 1facc0a40.
