---
track: A
prio: 60
status: open
type: bug
tags: [nilpy, lekkerzeilen, O]
blocked-by: []
summary: "MECHANISM, verified in source not inferred from timings: BShl(a,k) in compiler/builtin/promocore.pas:648 is `for i := 1 to k do r := BMulSmall(r, 2)` -- ONE FULL BIGNUM MULTIPLY PER BIT SHIFTED. BShr(a,k):660 builds 2^k by the same k-iteration loop and then runs a full BDivMod, which is why >> costs ~2.5x <<. So a Python shift is O(k) bignum multiplies where it should be a limb-level shift, and the cost is in the SHIFT COUNT, not the operand size. It SPRINGS for any NilPy program using << or >> with a nonsmall shift count -- hashing, RNGs, bit packing, serialisation -- and it is invisible in a benchmark that shifts by 1. MEASURED by lekkerzeilen-7a, isolated per-op, NilPy against CPython, ns/call: `<<` 15,159 vs 190, `>>` 38,023 vs 129 -- 80x and 295x. THE CONTROL IS IN THE SAME DATA AND IS WHAT MAKES THIS A MECHANISM RATHER THAN GENERAL SLOWNESS: xor is 3.9 ns vs CPython's 78, i.e. WE ARE 20x FASTER, mask is at par, and float add is 6.5 vs 66. Every other integer op is healthy, so the bignum representation is not the problem -- two operators are. FIX SHAPE: for k < 62 build the power of two directly (BFromInt(Int64(1) shl k)) instead of looping, turning k multiplies into one; properly, shift limbs. NOT A CALL-SITE PROBLEM: 7a has a bit-identical demo-side rewrite (x << 13 -> x * 8192, x >> 17 -> x // 131072) worth 133x on their xorshift, and that is a correct local workaround that leaves the defect live for every other NilPy program -- do not let it close this."
---

# Python `<<` and `>>` cost one bignum multiply per bit shifted

`compiler/builtin/promocore.pas:648`:

```pascal
function BShl(const a: TBig; k: Int64): TBig;
begin
  if k <= 0 then begin BShl := a; Exit; end;
  wasNeg := a.neg;
  r := a; r.neg := False;
  for i := 1 to k do r := BMulSmall(r, 2);     { <-- k multiplies }
  ...
```

and `:660`, `BShr`, builds its divisor the same way before a full `BDivMod`:

```pascal
  p2 := BFromInt(1);
  for i := 1 to k do p2 := BMulSmall(p2, 2);   { <-- k multiplies }
  BDivMod(a, p2, q, rem);
```

So `x << 13` is thirteen bignum multiplications and `x >> 17` is seventeen of
them plus a division. **The cost scales with the SHIFT COUNT, not with the
operand.** A test that shifts by 1 sees nothing.

## Why this is a mechanism and not "bignums are slow"

7a's isolated per-op measurements, NilPy against CPython (ns/call):

    <<     15,159   vs    190      80x SLOWER
    >>     38,023   vs    129     295x SLOWER
    xor         3.9 vs     78      20x FASTER
    mask        at par
    float +     6.5 vs     66      10x FASTER

**Every other integer operation is healthy or better.** The representation is
fine. Two operators walk a loop nobody else walks.

## The fix that is NOT this ticket

7a has a demo-side rewrite — `x << 13` -> `x * 8192`, `x >> 17` -> `x // 131072`
— which is exact for all Python ints including negatives, verified
byte-identical on both compilers, and takes their xorshift from 97,267 ns/call
to 732 ns (**133x**). That is a correct local workaround and it should land on
its own merits.

**It must not close this ticket.** It leaves the defect live for every other
NilPy program, and the next person to hit it will be someone writing a hash or
a serialiser who has no reason to suspect the shift operator.

## Suggested repair

While `k < 62`, `2^k` fits an `Int64`, so `BFromInt(Int64(1) shl k)` replaces
the whole loop with one construction — k multiplies become one multiply (or one
divmod). Beyond that, shift whole limbs and carry the remainder, which is the
textbook form and removes the loop entirely.

**Positive control for whoever builds it:** a shift by a LARGE count
(`x << 200`) must get faster by orders of magnitude, and a shift by 1 must not
regress. Assert both — a fixture that only shifts by a small count cannot tell
the two implementations apart, which is why this survived.

**AND THE REASON THE ORDINARY FIXTURE MISSES IT, in 7a's words: the SHIFT COUNT
is the independent variable and the OPERAND is the control — which is the
reverse of how anyone instinctively writes a bignum test.** Written the natural
way (one small shift, a big operand, assert the value) the test passes today,
passes after the repair, and certifies the bug in both directions.

**The reading makes a testable prediction that already held.** 7a's `>>` at
38,023 ns against `<<` at 15,159 is 2.51x, while their shift counts are 17 and
13 — a ratio of only 1.31. The loop alone does not account for it; `k`
multiplies **plus a `BDivMod`** does. Their third operand, `x << 5`, is the
cheapest of the three, exactly as per-bit cost predicts. That is confirmation
the source read alone does not give.
