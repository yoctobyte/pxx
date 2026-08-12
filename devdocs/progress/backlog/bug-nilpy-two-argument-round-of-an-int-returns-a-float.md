---
track: N
prio: 45
type: bug
blocked-by: []
summary: "round(6, 2) answers 6.0 where CPython answers 6 — the two-argument form always returns a float, whatever it was given. The one-argument round(6) is correct. Any report that rounds an integer to N places prints 6.0 where the oracle prints 6"
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

## Gate

A `.npy` diffed against CPython: `round` of an int with and without `ndigits`,
of a float with and without, of a variant holding each, negative `ndigits`
(`round(1234, -2)` is `1200`, an int), a bool (`round(True, 2)` is `1`), and
`str()` of each result so the int/float distinction is actually asserted.
