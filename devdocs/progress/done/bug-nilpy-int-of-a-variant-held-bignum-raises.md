---
track: N
prio: 40
type: bug
summary: "NilPy: int(x) where x is a variant-held arbitrary-precision int raises EVariantError instead of being the identity — and pyint_v, the variant-returning helper that would answer it, exists in pylib but is never emitted by the frontend"
status: done
owner: claude-A-N
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

## 2026-08-07 — FIXED, and the orphan is emitted

Taken straight after its sibling
[[bug-nilpy-int-of-a-long-decimal-string-narrows]], which is where the shape
came from: decide the type in the PARSER, produce the wide value in the
runtime.

**Three edits, plus one the measurement forced.**

1. `parser.inc`, the NilPy `int(` arm: a `tyVariant` argument types the `-200`
   node `tyVariant`. A variant may hold an arbitrary-precision int, so Int64 is
   not a type the result can have.
2. `ir.inc`, the `-200` variant arm: `pyint_v` instead of `VariantToInt64` —
   which is the routine that was *aborting*. So the orphan this ticket found is
   now emitted, and its runtime half stops being dead.
3. `pylib.pas`, `pyint_v`: a `VT_PROMO_INT64` payload is handed back as-is
   (int() of an int is the identity at any magnitude), rather than routed
   through `pyvar_to_int`, whose mod-2^64 narrowing is the right rule for the
   masked-cell idiom and the wrong one for `int()`.

4. **`PyInferExprType`'s `int(...)` CALL arm now answers `tyVariant`.** Not
   planned — caught by the differential. `def anyint(v): return int(v)` then
   `anyint(2**64)` answered **0**: the token scan registered an Int64
   *signature* over a body that now returns a variant, which is the silent ABI
   mismatch, and the return store quietly gave zero. A token scan cannot tell
   `int(<str>)` (promo) from `int(<variant>)` (variant) from `int(<int>)`
   (Int64), and tyVariant is the one answer that holds all three — it is also
   what that scan already answers for any call it cannot type. Deliberately
   scoped to the CALL: `int` the ANNOTATION (`PyAnnTypeAt`) and `int` the bare
   type name (`PyTypeFromTokenIndex`) still mean a 64-bit cell.

**One regression caught and fixed before landing**, worth recording because it
is exactly the "the old path was doing more than it looked like" trap:
`VariantToInt64` *parses strings* (it is Pascal's coercive Variant), so
`def g(v): return int(v)` with `g("12")` answered 12 on `pinned` and TypeError
the moment `pyint_v` took over — `pyvar_to_int` raises for a string, correctly,
because that rule is for a string in an ARITHMETIC context, not for `int()`
whose whole job on a string is to parse. `pyint_v` now handles `VT_STRING`
through `pystr_to_promo`, so a variant-held 30-digit string is as exact as the
statically-typed one. Net: strictly wider than what `pinned` accepted.

**On the "check for other orphaned `*_v`" note:** `pyneg_v` / `pyinvert_v` and
the rest are reached from `pyeval.pas`'s interpreter rather than from the
emitters, so the grep that found `pyint_v` over-reports. The two with no
reference anywhere in the tree are **`pyshl_v`** and **`pystr_repeat_v`**.
Recorded, not touched: unlike `pyint_v` there is no bug pointing at them, so
whether they are dead code or a not-yet-wired shift/repeat path is a question
for whoever needs one — deleting on a grep would be the same speculative edit
this ticket's author declined to ship.

**Verified**, self-hosted build at this commit, all diffed byte-identical
against CPython: `test_nilpy_int_promotion_default.npy` extended with `int()`
over a variant-held bignum (both signs), over container elements, through an
unannotated parameter, and over variant-held text including a 30-digit string;
the sibling's `test_nilpy_int_of_string_is_arbitrary_precision.npy` unchanged;
and a variant-consumer smoke (for-in element, dict value, list index, `sorted`,
`str`/`float`/`abs`, string repeat, `//`, comparisons). `.expected` regenerated
from CPython's own output. `tools/gate.sh quick` GREEN.

## Log
- 2026-08-07 — resolved, commit 1ac653821.
