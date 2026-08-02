---
track: N
prio: 60
type: bug
summary: "print(float) does not use Python's shortest-round-trip repr: 1/3 loses a digit, 0.1+0.2 prints 0.3 (hiding the error), 1e-20 prints WRONG DIGITS (1.000000000000001e-20), and the scientific-notation threshold differs (3e-05 vs 0.00003)"
---

# Float printing is not Python's `repr` — six distinct divergences

- **Type:** bug (NilPy — SILENT wrong output) — **Track N**
- **Found:** 2026-08-02 by a differential sweep against the CPython oracle
  (`tools/pydiff.py`).

## Measured

```python
for v in [0.1, 1/3, 1e20, 1e-20, 2.0, -0.0, 100.0, 1.5e300, 3.0e-5, 123456789.123]:
    print(v)
print(0.1 + 0.2)
print(1/3 + 1/3)
```

| expression | CPython | pxx |
| --- | --- | --- |
| `1/3` | `0.3333333333333333` | `0.333333333333333` |
| `1/3 + 1/3` | `0.6666666666666666` | `0.666666666666667` |
| `1e-20` | `1e-20` | `1.000000000000001e-20` |
| `3.0e-5` | `3e-05` | `0.00003` |
| `123456789.123` | `123456789.123` | `123456789.122999995946884` |
| `0.1 + 0.2` | `0.30000000000000004` | `0.3` |

`0.1`, `1e20`, `2.0`, `-0.0`, `100.0`, `1.5e300`, `7/2`, `7//2`, `7.0//2` and
`float("inf")` / `float("-inf")` all agree.

## The four separate faults, because they need different fixes

1. **Digit count.** `0.333333333333333` is 15 significant digits; a double needs
   **17** to round-trip, and Python emits the *shortest* string that round-trips
   (16 here). One digit is being dropped, so the value does not round-trip.

2. **Wrong digits, not just fewer.** `1e-20` printing as `1.000000000000001e-20`
   is not a truncation — it is a different number. The conversion is producing
   noise digits in the small-exponent path.

3. **Scientific-notation threshold.** Python switches to exponent form for
   `abs(v) < 1e-4` (`3e-05`) and for `>= 1e16`. pxx printed `0.00003`, so the
   low-end threshold is absent or set elsewhere. Note also the **two-digit
   exponent** (`3e-05`, not `3e-5`), which is part of the format.

4. **Over-expansion.** `123456789.122999995946884` is the exact binary value
   printed to excess precision instead of the shortest round-tripping form.

`0.1 + 0.2` → `0.3` is the same root cause as (1) seen from the friendly side:
rounding to too few digits happens to hide the representation error. It is still
wrong against the oracle, and it is the one most likely to be mistaken for
correct behaviour.

## Why this matters more than it looks

Python's `repr` contract is *round-trip*: `float(repr(x)) == x` for every finite
double. Every divergence above breaks it, so any NilPy program that serialises
floats through `str`/`print` — JSON, CSV, a config dump, a test's expected
output — loses precision silently and asymmetrically. It also means a `.npy`
regression test whose expected output contains a float is currently recording
pxx's rounding, not CPython's.

## Where to look

The Python-facing float formatting path, not Pascal's `Str`/`WriteLn` — Pascal
has its own (correct for Pascal) conventions and must not change. Check whether
the NilPy `print` of a float routes through a shared Pascal float-to-string
helper; if it does, this needs a NilPy-specific formatter rather than a change
to the shared one, or Track P/A regressions follow.

The algorithm is the shortest-round-trip one (Steele & White / Grisu / Ryu).
Getting it exactly right for all doubles is real work; getting (2) and (3) right
— wrong digits and the threshold — is separable and worth doing first, since a
wrong digit is a worse failure than a suboptimal digit count.

## Related, found in the same sweep

`repr` is not defined as a builtin at all (`error: undefined variable (repr)`),
so the round-trip property cannot even be spelled from NilPy source today. See
[[bug-nilpy-unsupported-protocols-repr-iter-getattr-delitem-hash]] for the
dunder side of that.

## Gate

A `.npy` diffed against CPython over a table of doubles covering: the six rows
above, both notation thresholds from either side (`1e-4`, `9.9e-5`, `1e16`,
`9.9e15`), negatives, subnormals, `float('inf')` / `-inf` / `nan`, and a
round-trip assertion `float(str(x)) == x` over the whole table.
