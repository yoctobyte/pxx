---
track: N
prio: 40
type: bug
summary: "NilPy: int(x) where x is a variant-held arbitrary-precision int raises EVariantError instead of being the identity — and pyint_v, the variant-returning helper that would answer it, exists in pylib but is never emitted by the frontend"
---

# `int()` of a variant-held bignum raises instead of being the identity

- **Type:** bug (ordinary Python refused) — **Track N**
- **Found:** 2026-08-06, as the residual of
  [[bug-nilpy-floordiv-mod-compare-and-float-narrow-a-variant-held-bignum]],
  which fixed the four SILENT members of that family. This one raises, so it
  was split out rather than folded in.

## Measured (self-hosted, after the fixes above)

```python
x = 2**64
print(int(x))
# CPython 18446744073709551616
# pxx     Runtime error: EVariantError, promotable integer
#         18446744073709551616 does not fit an Int64
```

`int()` of an int is the identity in Python, at any magnitude. A statically
promo-typed value is already correct — `test_nilpy_int_promotion_default.npy`
covers `print(int(n))` and it passes. It is the VARIANT-held case that fails,
which is the ordinary shape for a module-scope binding, a container element or
an unannotated parameter.

## Where it goes wrong

`PXXDBG=a.ir:<proc>` on `def f(): x = 2**64; print(int(x))` shows the `int()`
call lowering to a helper typed **`tk=13`** — `tyInt64` — i.e. the narrowing
`pyvar_to_int`. So this is a FRONTEND routing choice, not missing runtime code.

**The runtime side already exists and is orphaned.** `pyint_v(const v: Variant):
Variant` is declared and defined in `compiler/builtin/pylib.pas`, and
`grep pyint_v compiler/pyparser.inc` finds **nothing** — the frontend never
emits it. The likely fix is to route `int()` over a variant argument to that
helper (and make it pass a heap-tier promo straight through, which it does not
do today: it also goes through `pyvar_to_int`).

I patched `pyint_v` to be promo-aware while resolving the parent ticket,
measured that it changed nothing because it is unreachable, and reverted it
rather than ship a speculative edit. Do the frontend half and the runtime half
together, or the runtime half stays dead.

Worth a moment while in there: check whether any OTHER declared-but-unemitted
`*_v` helper is in the same state — an orphan pair like this is usually not
unique.

## Gate

Per-fix loop. Extend `test/test_nilpy_int_promotion_default.npy` (which already
carries the statically-typed `int(n)` case) with `int()` over a variant-held
bignum, both signs, plus `int()` of an ordinary variant int and of a float, all
diffed against CPython with `tools/pydiff.py`.
