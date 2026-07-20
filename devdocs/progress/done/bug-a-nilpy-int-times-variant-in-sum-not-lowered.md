---
track: A
prio: 60
type: bug
---

# NilPy: `total = total + k * v` with a VARIANT operand fails to lower

Found 2026-07-20 while landing [[feature-nilpy-missing-builtins]]; confirmed
PRE-EXISTING on a compiler built from committed HEAD with that work reverted,
so it is not part of it.

## Repro

```python
xs = [10, 20]
total = 0
for v in xs:
    total = total + 2 * v      # v is a for-in VARIANT
print(total)                   # CPython 60
```
```
error: IR_UNSUPPORTED: frontend could not lower AST node (kind 5) — a frontend
gap, would miscompile
```

Kind 5 is `AN_BINOP`. Each half works ALONE — `print(2 * v)` lowers (pymul_v),
and `total = total + v` lowers — so it is the nesting of a variant-producing
multiply inside an addition that has no path: the `+` sees a Variant left and a
Variant-typed BINOP right, and the variant-add lowering evidently only handles
a leaf operand there.

Loud, not silent, which is why it is a 60 and not urgent. But it blocks the
most ordinary accumulation loop there is, and every for-in loop variable is a
variant, so it will be hit constantly by real corpus code.

## Shape

`ir.inc`'s variant arithmetic (the `pymul_v` / variant-add arms) should lower a
nested variant BINOP operand by materialising it into a variant temp first,
rather than requiring a directly-addressable operand. Compare the
`IRVariantAddr` path — the same "a variant RVALUE has no address" constraint
that [[project_variant_scalar_unbox_landed]] records.

## Gate

`test-nilpy` green + `--tier quick` + self-host byte-identical, with the repro
plus `total = total + v * v`, `total = total + (v + 1) * 2` and a float variant
matching CPython.

## Log
- 2026-07-20 — resolved, commit 08775145.
