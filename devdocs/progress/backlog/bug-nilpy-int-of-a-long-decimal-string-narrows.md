---
track: N
prio: 55
type: bug
summary: "NilPy: int('<30 digits>') wraps mod 2^64 instead of producing an arbitrary-precision int — int('123456789012345678901234567890') prints -4362896299872285998"
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
