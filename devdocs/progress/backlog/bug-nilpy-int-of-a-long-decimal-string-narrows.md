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
