---
track: A
prio: 50
type: bug
blocked-by: []
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
