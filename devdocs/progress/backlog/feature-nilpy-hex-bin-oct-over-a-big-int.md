---
track: N
prio: 55
type: feature
blocked-by: decide-nilpy-int-promotion-costs-10x-on-ordinary-loops
summary: "hex/bin/oct take Int64, so they stop matching the moment every NilPy int is promotable — they need a PXXPromoToBase in promocore plus a frontend lowering, NOT a pylib overload (a PromoInt parameter cannot reach the runtime)"
---

# `hex` / `bin` / `oct` over an arbitrary-precision int

- **Type:** feature (NilPy) — **Track N**, with a Track A half in `promocore.pas`
- **Filed:** 2026-08-04, split out of
  [[decide-nilpy-int-promotion-costs-10x-on-ordinary-loops]], where it was only
  recorded as a finding.

Python's `hex`, `bin` and `oct` take arbitrary precision:

```python
print(hex(2 ** 70))     # 0x400000000000000000
```

`pylib.pas` declares them as `function hex(n: Int64): AnsiString`. Of seventeen
builtins and container operations surveyed with a promotable-int argument, these
three are the **only** ones that stop matching — everything else
(`str`, `abs`, `float`, `chr`, `divmod`, `max`, `min`, `round`, `pow`, indexing,
slicing, `*` repeat, `for … range`) already copes. So the blast radius is three.

## The obvious fix does not work, and the reason is measured

A `PromoInt` overload in `pylib` cannot be written: **a `PromoInt` PARAMETER
cannot be handed to the promo runtime at all.** With a LOCAL, both
`PXXPromoToStr(@n)` and `PXXPromoToStr(Pointer(n))` are correct; with the same
value arriving as a parameter, both return a pointer
([[bug-a-promoint-shr-yields-nothing-and-a-machine-int-cast-yields-the-slot-address]],
the 2026-08-04 addendum). Writing the digit loop in Pascal is blocked twice over
anyway: `shr` on a `PromoInt` yields nothing, and `Integer(n)` yields the slot
address, so a digit cannot index a digit table.

It is also NOT a unit-name problem — that was suspected and disproved: the unit
was renamed `promoint` → `promocore` for clarity (`c4f6ef4b9`), but `uses
promoint` beside a `PromoInt` variable had always resolved correctly.

## Shape of the fix

1. **`PXXPromoToBase(a: Pointer; base: Integer): AnsiString`** in
   `promocore.pas`, beside `PXXPromoToStr` — which already renders base 10
   straight off the limbs and can call `PXXPromoToInt64` directly, so neither
   Pascal-side gap applies. Sign handling follows Python: `hex(-255)` is
   `-0xff`, not a two's-complement form.
2. **A frontend lowering** for `hex`/`bin`/`oct` when the argument is
   promo-typed, to that routine — the same shape as `**` → `pypow_v` and the
   other name-keyed lowerings. The frontend already knows how to hand a promo
   value to a runtime helper; that is how every promo operator works and why
   `writeln(n)` prints a bignum correctly.
3. `pylib`'s existing `Int64` versions stay for the native case.

Note step 2 must go through `PyUserShadowsProc`, like every other name-keyed
lowering, or a user `def hex(x)` stops being honoured
([[bug-nilpy-user-def-does-not-shadow-a-pylib-builtin]] — that ticket found an
IR-level rewrite doing exactly this and had to guard it).

## Why it is blocked

Nothing forces this until every NilPy int is promotable. Today `hex(255)` is an
`Int64` call and correct; only a wide literal or a grown value reaches the gap,
and both are rare until the promotion default lands. Unblock together.

## Gate

A `.npy` diffed against CPython: `hex`/`bin`/`oct` of a small int, of `2 ** 70`,
of a negative small int and a negative big one, of `0`, and of a value that has
spilled to the heap tier and back; plus a user `def hex(x)` still shadowing;
plus the `Int64` path unchanged for native values.
