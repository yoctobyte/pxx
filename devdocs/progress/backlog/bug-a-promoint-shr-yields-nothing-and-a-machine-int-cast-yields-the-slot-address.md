---
track: A
prio: 50
type: bug
summary: "PromoInt in PASCAL: `n shr k` produces nothing (shl is fine), and Integer(n)/Int64(n) yields the SLOT ADDRESS instead of the value — both silent, both block writing base-conversion (hex/bin/oct) over a promotable int in Pascal"
---

# `PromoInt`: `shr` yields nothing, and a machine-int cast yields the slot address

- **Type:** bug (Track A — promotable-int lowering) — **silent wrong value**
- **Found:** 2026-08-04, checking whether `hex`/`bin`/`oct` can be written over a
  `PromoInt` in Pascal (they must be, once
  [[decide-nilpy-int-promotion-costs-10x-on-ordinary-loops]] lands: Python's
  `hex` takes arbitrary precision).

## Measured — plain Pascal, no NilPy involved

```pascal
program t;
var n, d: PromoInt;
begin
  n := 255; d := n shl 1; writeln(d);   { 510  — correct }
  n := 255; d := n shr 1; writeln(d);   { prints NOTHING }
  n := 255; d := n shr 4; writeln(d);   { prints NOTHING }
  n := 255; d := n div 16; writeln(d);  { 15   — correct }
  n := 255; d := n mod 16; writeln(d);  { 15   — correct }
  n := 12;  writeln(Int64(n));          { 4342664 — GARBAGE }
  n := 12;  writeln(Integer(n));        { 4342680 — GARBAGE }
end.
```

Everything else works: `*`, `div`, `mod`, `and`, comparisons and `writeln` of a
promotable int are all correct, and `n := 1; for i := 1 to 70 do n := n * 2`
prints `1180591620717411303424` exactly.

## Two defects

1. **`shr` produces nothing.** `shl` is correct at the same widths, so this is
   the one arm rather than the shift family. Note NilPy's own `>>` works — the
   frontend routes shifts through the promo runtime deliberately
   ([[project_promotable_int_stages123]]) — so this is the PASCAL-side lowering.
2. **A cast to a machine integer yields the SLOT ADDRESS.** `4342664` for the
   value 12 is a pointer, which is exactly the documented rvalue model leaking:
   *"an rvalue is the SLOT ADDRESS, not the payload"*. `Int64(n)` needs to lower
   to the demote helper (`PXXPromoToInt64` already exists in `promoint.pas` and
   is correct) instead of a plain reinterpret.

The second is the one that BLOCKS things: with no way to get a small promotable
int back into a machine integer, a digit loop cannot index a digit table, so
base conversion cannot be written in Pascal source at all.

## Why it matters now

`hex`/`bin`/`oct` in `pylib.pas` take `Int64`, and they are the only three of
seventeen surveyed builtins that stop matching once every NilPy int is
promotable. The natural fix — a `PromoInt` overload doing `while n <> 0 do begin
d := n and 15; …; n := n shr 4 end` — needs **both** of these working.

(There is a second route that sidesteps both: put base conversion in
`promoint.pas` itself, beside `PXXPromoToStr`, which already renders base 10
straight off the limbs and can call `PXXPromoToInt64` directly. That is probably
the better implementation anyway — but these two are real bugs regardless, and
anyone writing ordinary Pascal against `PromoInt` will hit them.)

## Gate

`make test` + self-host byte-identical, plus a Pascal test asserting `shr` at
several widths against the `div`-by-power-of-two answer, and `Int64(n)`/
`Integer(n)` round-tripping a small promotable int — including one that has
spilled to the heap tier and back.
