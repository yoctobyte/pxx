---
track: N
prio: 55
type: bug
summary: "NilPy: int('<30 digits>') wraps mod 2^64 instead of producing an arbitrary-precision int — int('123456789012345678901234567890') prints -4362896299872285998"
status: done
owner: claude-A-N
---

# `int()` of a decimal string wider than 64 bits narrows

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-06, bughunting, `tools/pydiff.py` against CPython.

## Measured (self-hosted binary at `412fda7a3`)

```python
s = "123456789012345678901234567890"
n = int(s)
print(n)        # CPython 123456789012345678901234567890   pxx -4362896299872285998
print(n + 1)    # CPython 123456789012345678901234567891   pxx -4362896299872285997
print(str(n))   # CPython 123456789012345678901234567890   pxx -4362896299872285998
```

`-4362896299872285998` is the value taken mod 2^64, read signed. Nothing raises.

A wide *literal* is handled correctly — `print(10**30 + 1)` and `print(2**64)`
both agree with CPython — so this is the **string parse** path specifically, not
the promotable-int representation.

## Note for whoever takes it

`promocore.pas` already exports `PXXPromoFromStr` (and `PromoFromStrCached` /
`PromoFromStrRemember`), which is exactly this conversion; the NilPy `int(str)`
lowering is not reaching it and falls to the Int64 string-to-int path. Check
what the frontend emits for `int(<str>)` before assuming a runtime gap —
`PXXDBG=a.ir:<proc>` names the helper actually called.

## Related

- [[bug-nilpy-floordiv-mod-compare-and-float-narrow-a-variant-held-bignum]]
- [[bug-nilpy-augmented-assignment-truncates-to-32-bits]]

## Gate

Per-fix loop. A `.npy` test round-tripping `int(s)` / `str(n)` for decimal
strings of 20, 30 and 60 digits, both signs, diffed against CPython.


## 2026-08-06 — attempted, reverted, and what it cost

The runtime half is easy and the FRONTEND half is the real work. Recording the
dead end so the next attempt starts past it.

A `pystr_to_int_v(s): Variant` was written — digit-count gate (>18 digits takes
the exact path, everything else delegates to `pystr_to_int` so its ValueError
wording and whitespace/sign handling stay the single source of truth), then
`PXXPromoFromStr` + `PXXPromoToVariant`. That part is straightforward.

Routing `int(<str>)` to it in `ir.inc` then broke ORDINARY `int()`:

```
print(int("42"))      ->  5587984        { the variant's SLOT ADDRESS }
```

The frontend types every `int(...)` as `tyInt64` (`PyTypeFromTokenIndex` and the
two other inference sites), so a consumer reading `ASTTk` takes the returned
variant's address for the value. Retyping the call node during lowering —
`ASTTk[node] := Ord(tyVariant)`, the same move the float-div arm makes — was
**not enough**: `write` reads its argument's type *before* lowering the
argument, so the assignment lands too late for it.

So the fix needs the type decided in the FRONTEND, not patched during lowering:
`int()` over a string argument has to be typed variant (or promotable) where the
inference happens. That is a wider change than it looks — those three inference
sites answer for `int` the annotation as well as `int()` the call.

Both halves were reverted rather than left half-applied; the helper was removed
too, since an unreferenced runtime function is dead code (same call as the
orphaned `pyint_v` in
[[bug-nilpy-int-of-a-variant-held-bignum-raises]], which is the sibling of this
ticket and wants the same frontend work).

**Take these two together.** They are one problem — `int()` cannot express a
result wider than Int64 — seen from the string side and the variant side.

## 2026-08-07 — FIXED: `int(<str>)` is typed a promotable int

The 08-06 note is right that the frontend half is the work, and right about
where: the type has to be decided at PARSE time because `write` reads its
argument's type before lowering the argument. What it did not reach is that the
right type was already sitting there — a wide **literal** has been typed
`tyPromoInt64` since NilPy got promotable ints, and that is why `10**30 + 1`
was correct all along. `int(<str>)` is the same thing arriving as data instead
of as source, so it gets the same type.

**Three edits.**

1. `parser.inc`, the NilPy `int(` arm: a `tyString`/`tyAnsiString` argument
   types the `-200` node `tyPromoInt64` (and `LastExprTk` with it). `tyChar`
   deliberately stays on the Int64 path — a one-character string cannot exceed
   9. Everything else is untouched, so `int(<int>)`, `int(<float>)` (the -203
   Trunc intrinsic), `int(<variant>)` and the two-argument radix form keep the
   types they had.
2. `ir.inc`, the `-200` lowering: a string argument whose CALL node is
   promo-typed goes to a fresh promo temp slot, and the slot address is the
   result — which is what the value of a promo-typed expression already is
   everywhere else (`IRPromoAddrOf`).
3. `pylib.pas`: `pystr_to_promo(dst, s)`. Validates first and then hands the
   text to `PXXPromoFromStr`. The validation is spelled out rather than
   delegated because `Val` is precisely the narrowing that has to go, while the
   ValueError wording must stay byte-identical to `pystr_to_int`'s — and
   because `PXXPromoFromStr` STOPS at the first non-digit, so without an
   explicit check `int("12x")` would quietly answer 12 where `pystr_to_int`
   raises.

**The one thing that cost time**, recorded so it is not re-derived: inside the
`-200` arm, `item` is the AN_ARG node, not the call — `argVal := ASTLeft[item]`
is what gives it away. Testing `ASTTk[item]` for the promo type therefore always
answered "no" and the branch never fired, while the AST dump plainly showed
`kind=8 tk=28 ival=-200`. `PXXDBG=a.ast` said the parser had done its job in
about ten seconds; reasoning about it would have blamed the parser.

**Verified**, self-hosted build at this commit, all diffed byte-identical
against CPython: the new
`test/test_nilpy_int_of_string_is_arbitrary_precision.npy` (20/30/60 digits,
both signs, `str(int(s)) == s` round-trip, `+ * - // %` and comparisons on the
result, the ordinary small cases — list index, `range()`, whitespace, `"0"` —
and ValueError on `"12x"` / `"abc"` / `""`), plus a consumer smoke over an
annotated `int` parameter, a dict key, string repeat and index, `sorted`/`max`/
`min`/`sum`, `float()`, `str()`, `abs()`, `hex()` and `//`/`%`.
`tools/gate.sh quick` GREEN.

**Still open, and it is the sibling:**
[[bug-nilpy-int-of-a-variant-held-bignum-raises]]. `int(10**30 + 1)` still
raises `does not fit an Int64` — identically on `pinned`, so it is not a
regression from this — because `**` yields a VARIANT and the `-200` variant arm
narrows through `VariantToInt64`. The test says so at the point where it would
otherwise cover it. Same one problem seen from the other side, and the shape
built here (parse-time promo typing + a dst-first runtime helper) is what it
wants too.

## Log
- 2026-08-07 — resolved, commit 80b2cd5af.
