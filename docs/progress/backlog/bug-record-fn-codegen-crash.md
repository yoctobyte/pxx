# Context-sensitive runtime crash: record-returning fn with nested loops over dynarray fields

- **Type:** bug (compiler / codegen)
- **Status:** backlog
- **Owner:** — (track A)
- **Opened:** 2026-06-19 (track B, building lib/rtl/bignum)
- **Relation:** referenced from `lib/rtl/bignum.pas` (the original fused BigMul was
  rewritten to avoid this); possibly the same root cause as the maze demo runtime
  segfault (unconfirmed — see demo(maze) commit).

## Symptom

A unit function that returns a record containing a dynamic array, and builds it
via a nested `for`/`for` + `while`-carry loop reading two dynarray-field operands
(`a.limbs[i] * b.limbs[j]`), **segfaults at runtime** — even though:

- the identical algorithm runs correctly when written inline in `program` scope
  (not as a unit function), and
- a *minimal* unit reproduction of the same function body does NOT crash.

So it is context-sensitive: it appears only inside the full `bignum` unit
(surrounded by the other routines), which points at register pressure / codegen
state rather than the algorithm. Compiles clean; crashes only when run.

The crashing shape (schematically):

```pascal
function BigMul(const a, b: TBigInt): TBigInt;   { TBigInt = record neg: Boolean; limbs: array of Int64; end }
var r: TBigInt; i, j, k, na, nb: Integer; carry, cur: Int64;
begin
  ...
  for i := 0 to na - 1 do
  begin
    carry := 0;
    for j := 0 to nb - 1 do
    begin
      cur := r.limbs[i + j] + a.limbs[i] * b.limbs[j] + carry;
      r.limbs[i + j] := cur mod BIG_BASE;
      carry := cur div BIG_BASE;
    end;
    k := i + nb;
    while carry > 0 do begin cur := r.limbs[k] + carry; r.limbs[k] := cur mod BIG_BASE; carry := cur div BIG_BASE; k := k + 1; end;
  end;
  ...
  BigMul := r;
end;
```

## Workaround in place

`bignum.BigMul` was reimplemented on the proven primitives (`BigMulSmall` +
limb-shift + `BigAdd`), which does not crash. That keeps the lib correct but
hides the codegen bug; it should still be fixed (it will bite other
record-returning numeric kernels).

## Direction

Reproduce against a freshly stabilized compiler (the bignum WIP was last built
against pinned v9; confirm it still reproduces post interface-refcounting), then
bisect the codegen for nested-loop dynarray-field index expressions inside a
record-returning function. Likely related to the nested-index load-width /
register-pressure landmines already seen in the compiler history.

## Log
- 2026-06-19 — opened by track B. Inline + minimal-unit repros do NOT crash; only
  the full `bignum` unit does. Worked around in the lib; needs a real fix.

## Re-verify on v10 (2026-06-19)

Last seen against pinned **v9 mid-WIP**. Track A pinned **v10** (`93ad58a`) —
freshly stabilized, binary+builtin coherent (the v9 era had the
bug-pinned-stable-reads-live-builtin mix). **Before bisecting, reproduce against
v10**: the crash may have been a WIP artifact and already be gone. If gone,
close; if it reproduces, bisect on the clean compiler.

## Re-verified: REPRODUCES on v10 (2026-06-19, track B)

Confirmed on the coherent pinned **v10** — not a v9 WIP artifact. Inside the full
`lib/rtl/bignum.pas` unit, calling `BigShiftLimbs` (or `BigMul`, which uses it)
segfaults; the identical function body in plain `program` scope does NOT crash.
Still context-sensitive (full-unit only). `BigMul`/`BigShiftLimbs` were removed
from the bignum interface for now; `BigMulSmall` (the verified path) covers the
factorial oracle. Restore `BigMul` once this is fixed.
