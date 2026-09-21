---
track: A
prio: 60
status: done
type: bug
tags: [nilpy, lekkerzeilen, O]
blocked-by: []
summary: "FIXED 8cbec7eab, gate GREEN. MECHANISM WAS: BShl ran one full bignum multiply PER BIT (`for i := 1 to k do r := BMulSmall(r,2)`, each allocating) and BShr built 2^k the same way and then ran a full BDivMod, which binary-searches every quotient digit over [0,BIG_BASE) -- ~30 BMulSmall per limb. Both now step by BIG_SHIFT_CHUNK=33 bits, ceil(k/33) operations instead of k, with a new one-pass BDivSmall so >> avoids BDivMod entirely. 33 is bounded by the INNER TERM not the base (limb < 1e9, 2^33 = 8.59e9, product < 2^63); 34 overflows SILENTLY -- verified, it breaks 61 of 792 differential rows. MEASURED min-of-3, ns/call, `mul` unchanged as control: shl_13 14030->5139 (2.7x), shl_26 23579->5091 (4.6x), shl_200 199694->36058 (5.5x), shr_1 31302->4914 (6.4x), shr_17 41732->4881 (8.6x), shl_1 unchanged as it always was one multiply. Correctness: 792 rows across 22 values x 18 shift counts byte-identical to CPython, plus 4000 random round-trips |v|<=10^25 k in 0..260 with the identities v<<k == v*2**k and v>>k == v//2**k, which reach the answer by a different code path. TWO RESIDUALS, BOTH MEASURED AND NEITHER CHASED, and they are why this is worth reopening rather than forgetting: (1) `x << 13` is still ~2x `x * 8192` (5139 vs 2400) although both now do exactly ONE BMulSmall, so ~2600 ns sits in the SHIFT DISPATCH (PXXPromoShl/PromoShiftCount) rather than the arithmetic -- which is why 7a's call-site rewrite is still faster than the fixed operator; (2) BDivMod STILL binary-searches every quotient digit, so general `//` and `%` on bignums carry ~30 BMulSmall per limb and nobody has measured what that costs on large operands. THE REPAIR THIS TICKET ORIGINALLY SUGGESTED -- shift limbs -- IS UNAVAILABLE: the magnitude is base-1e9, DECIMAL, so a binary shift is a genuine multiply or divide. Inert until a pin carries promocore.pas."
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
