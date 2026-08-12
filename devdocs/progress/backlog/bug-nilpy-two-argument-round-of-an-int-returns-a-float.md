---
track: N
prio: 45
type: bug
blocked-by: []
summary: "round(6, 2) answered 6.0 where CPython answers 6. PARTIALLY FIXED 2026-08-12 — a statically-typed int with a non-negative literal ndigits is now the identity; a VARIANT/promo argument, a negative ndigits and a computed one still take the float path, and round(2**70, 2) still loses the precision entirely. Finishing it is a pylib change (so: stabilize+pin)"
---

# Two-argument `round()` of an int returns a float

- **Type:** bug (wrong value/type) — **Track N** (pylib builtin)
- **Found:** 2026-08-12, differential bug hunting against CPython — it was the
  residue left after
  [[bug-nilpy-an-override-returning-a-different-type-than-the-base-reads-float-bits]]
  was fixed, in `str(round(self.area(), 2))`.

```python
print(round(6, 2))      # pxx: 6.0     CPython: 6
print(round(6))         # pxx: 6       CPython: 6      -- correct
print(round(6.5, 2))    # pxx: 6.5     CPython: 6.5    -- correct
```

CPython's rule: `round(x, n)` returns an **int** when `x` is an int (whatever
`n` is), and a float when `x` is a float. NilPy's two-argument form routes
everything through the float path.

It shows up wherever a value that happens to be integral is formatted for a
report — `str(round(total, 2))`, `print(round(count, 2))` — and prints `6.0`
where every other implementation prints `6`. Also true through a variant: a
list element holding `6` gives `6.0` too.

## 2026-08-12 — PARTIALLY fixed, and this is the part that remains

Landed: a statically-typed integer argument with a **non-negative literal**
`ndigits` is now the identity, which is what CPython does — `round(6, 2)` is 6,
`round(count, 3)` keeps its int, and the one- and two-argument forms finally
agree with each other. Test: `test/test_nilpy_round_ndigits_keeps_int.npy`.

Still on the float path, all measured after the fix:

| call | pxx | CPython |
| --- | --- | --- |
| `round(1234, -2)` | `1200.0` | `1200` (an int — it really does round) |
| `round(6, n)` for a variable `n` | `6.0` | `6` |
| `round(lst[0], 2)` (a VARIANT holding 6) | `6.0` | `6` |
| `round(True, 2)` | `1.0` | `1` |
| `round(2 ** 70, 2)` | `1.1805916207174113e+21` | the exact integer |

The last row is the bad one: an arbitrary-precision int loses its precision
entirely, because a promo/variant argument is unboxed to a double by the
`pyvar_to_float` wrap BEFORE the two-argument branch is reached (parser.inc,
the float-intrinsic site) — by then the intness is gone.

Finishing it needs a pylib routine that rounds an INT to n digits and returns
an int (identity for n >= 0, decimal rounding for n < 0) plus a variant-aware
twin, and the variant unboxing above has to be deferred when the call turns out
to have two arguments. That is a `compiler/builtin` change, so it also needs
stabilize+pin — which is why it was not folded into the frontend-only fix.

## Gate

A `.npy` diffed against CPython: `round` of an int with and without `ndigits`,
of a float with and without, of a variant holding each, negative `ndigits`
(`round(1234, -2)` is `1200`, an int), a bool (`round(True, 2)` is `1`), and
`str()` of each result so the int/float distinction is actually asserted.
