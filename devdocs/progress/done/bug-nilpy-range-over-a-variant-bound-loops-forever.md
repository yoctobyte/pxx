---
track: N
prio: 75
type: bug
---

# `for i in range(n)` LOOPS FOREVER when n is a variant

- **Type:** bug (NilPy, INFINITE LOOP) — **Track N**
- **Found and FIXED:** 2026-08-02, by a differential sweep against the CPython
  oracle. Surfaced as `exit: pxx=-15` on an unrelated probe — the program was
  killed, not wrong.

## Measured

```python
def gen(n):
    out = []
    for i in range(n):
        out.append(i * i)
    return out
print(gen(4))          # CPython [0, 1, 4, 9]     pxx HANGS
```

The boundary is sharp, and it is why nothing caught this:

| form | result |
| --- | --- |
| `range(4)` — literal | ok |
| module-level `n = 4`, `range(n)` | ok |
| `def f(n: int)` — ANNOTATED parameter | ok |
| **`def f(n)` — bare parameter** | **HANGS** |
| a local copied from a bare parameter | HANGS |
| `while i < n` with the same parameter | ok |
| `range(0, n)` | HANGS |

An unannotated parameter is a **variant**, and that is the most ordinary shape
in Python. Every corpus test that used `range` either used a literal or an
annotated parameter.

## Cause

The loop lowers to `i < stop` with the counter `i` typed `tyInteger`. When
`stop` is a variant, that compares the counter against the variant's **BOX**
(a pointer-sized value), which is always larger — so the condition is
permanently true.

Note `while i < n` was fine: that comparison goes through the variant-aware
runtime path. It is the same static-vs-variant split recorded in
`project_nilpy_static_vs_variant_operand_paths_diverge` — the hand-built loop
comparison never reached the runtime helpers.

## Fix

New `PyUnboxRangeBound` wraps a variant bound in `pyvar_to_int`, applied to
start, stop AND step (any of them can be a parameter). Non-variant nodes are
returned unchanged, so the literal and int-typed paths are untouched.
`pyvar_to_int` also applies Python's numeric rules and raises TypeError for a
non-number, which is what `range("x")` should do anyway.

## Verified

`test/test_nilpy_range_variant_bound.npy`, wired into `make test-nilpy`,
byte-identical to CPython. The pre-fix binary **hangs** on it — confirmed by
building it and timing out.

Covers: bare-parameter bound, two-argument, three-argument with a positive
runtime step, annotated parameter, a zero-length range, a comprehension over a
parameter bound, and the literal / module-variable forms as controls.

## Found alongside, NOT fixed here

A NEGATIVE step passed at runtime yields an empty range — the loop direction is
chosen at compile time from a literal step. Distinct defect, filed as
[[bug-nilpy-range-negative-runtime-step-yields-empty]]. Confirmed it is not a
consequence of this fix: the pre-fix binary did not hang on that shape.

Also noted: `list(range(3))` — `range` as a VALUE rather than a for-header —
is not supported (`undefined variable (range)`). Loud, so not in this family.
