---
track: N
prio: 55
type: feature
blocked-by: decide-nilpy-int-promotion-costs-10x-on-ordinary-loops
summary: "hex/bin/oct take Int64, so they stop matching the moment every NilPy int is promotable — they need a PXXPromoToBase in promocore plus a frontend lowering, NOT a pylib overload (a PromoInt parameter cannot reach the runtime)"
status: done
owner: claude-AN
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


## Resolved 2026-08-04 — and it was reachable ALREADY, not only after the promotion default

This ticket said "blocked on the promotion default: nothing reaches the gap
until every NilPy int is promotable". That is wrong, and measuring it first is
what unblocked the work: a **wide literal** already types promo today, so

```python
x = 1180591620717411303424
print(hex(x))       # error: no overload of hex matches — candidates: hex(Int64)
```

fails on current HEAD. Unblocked and done now rather than waiting.

### `PXXPromoToBase(a: Pointer; base: Integer)` in promocore

Bases 2, 8 and 16 are all powers of two, so `BMagToBase` reads **bit groups**
out of the byte buffer `BMagToBuf` already produces (base 256, little-endian)
rather than dividing the bignum once per digit. Octal is the one that does not
nest inside a byte — 3 does not divide 8 — so it walks a bit index rather than
assuming digits align, and the `oct(2**70)` row exists to pin that.

Digits are built into a `SetLength`'d buffer and filled from the end, never by
prepending in a loop ([[project_pxx_string_concat_in_loop_is_quadratic]]).

Sign follows Python: `hex(-255)` is `-0xff`, not a two's-complement form, so
only the magnitude is converted and the sign is carried separately. Zero is
`0x0`, matching what pylib's Int64 `hex` already produces — the two spellings
must agree, since which one a program reaches depends only on whether its value
happened to grow.

promocore is exception-free by design, so an out-of-range base returns an
unmistakable marker rather than a plausible wrong rendering.

### The frontend lowering, and the two things that made it hard

Intercepted in `ParseFactor` beside the other name-keyed NilPy lowerings,
guarded by `PyUserShadowsProc` (verified: a user `def hex(x)` still wins). A
NON-promo argument **rewinds** to the ordinary Int64 overload, so native values
keep today's path untouched.

Two failures on the way there, both silent segfaults, both found by dumping IR
rather than by reasoning:

1. **`PXXPromoToBase` was implementation-only.** `PXXPromoToStr` is declared in
   promocore's interface as `function  PXXPromoToStr` — with TWO spaces — which
   is why a `grep "function PXXPromoToStr"` had suggested it was not. Without an
   interface declaration the parser had no parameter types to match against.
2. **`TypeIsOrdinal` includes `tyPointer`.** `IRLowerCallArg`'s promo arm
   narrows a promo argument through `PXXPromoToInt64Wrap` for any ORDINAL
   parameter — and 17/tyPointer sits in the 15/16/17 group with
   tyNativeInt/tyNativeUInt. So a Pointer parameter got a narrowed VALUE where it
   wanted an ADDRESS, and the callee dereferenced it. A new arm passing
   `IRPromoAddrOf` had to go **before** the narrowing arm, not after — putting it
   after changed nothing and looked like the fix had failed.

That second one is the reusable part: **any frontend lowering that wants to hand
a promo value to a promocore entry point now works with an ordinary `AN_CALL`**,
instead of having to build IR by hand the way `writeln` and the operators do.

### Verified

`test/test_nilpy_hex_bin_oct_bigint.npy` + `.expected`, wired into
`make test-nilpy`: the native path unchanged (including 0 and negatives), an
arbitrary-precision hex/oct/bin, a 2^100 value, negatives at both tiers, the
values either side of the machine-word boundary, and the result used as an
ordinary string. All diffed against CPython, identical. A user `def hex(x)`
still shadows. `test_promoint`, `_bitwise` and `_overflow` unchanged.
`tools/gate.sh quick` GREEN, self-host byte-identical.

## Log
- 2026-08-04 — resolved.
- 2026-08-04 — resolved, commit 762c7addf.
