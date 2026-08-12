---
track: N
prio: 50
type: bug
blocked-by: []
summary: "`f\"{7.5:.0f}\"` and `\"%.0f\" % 7.5` both answer 7 where CPython answers 8: the formatter rounds a tie toward zero instead of to even, so every value whose lower candidate is ODD formats one off (1.5->1, 3.5->3, 7.5->7, -1.5->-1). The round() builtin is correct on the same values, so the two disagree with each other as well as with CPython"
---

# Float formatting rounds ties toward zero, not to even

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-12, differential bug hunting against CPython — a `.0f`
  format spec in an f-string.

CPython formats floats with **round-half-to-even** (IEEE 754's default, and what
`printf` does on glibc). NilPy's formatter rounds ties toward zero.

| value | `f"{v:.0f}"` / `"%.0f" % v` pxx | CPython | `round(v)` pxx |
| --- | --- | --- | --- |
| `0.5` | `0` | `0` | `0` |
| `1.5` | **`1`** | `2` | `2` |
| `2.5` | `2` | `2` | `2` |
| `3.5` | **`3`** | `4` | `4` |
| `7.5` | **`7`** | `8` | `8` |
| `-0.5` | `-0` | `-0` | `0` |
| `-1.5` | **`-1`** | `-2` | `-2` |
| `-2.5` | `-2` | `-2` | `-2` |

The rows that agree are the ones where the even candidate happens to be the
one nearer zero — i.e. it agrees exactly half the time, by coincidence.

Two things make this worth more than its size:

1. **It is a formatted number.** `f"{total:.0f}"` in a report is the last step
   before a human reads it, and being one out on half the ties is invisible.
2. **`round()` and the formatter disagree with each other.** `round(7.5)` is 8
   and `f"{7.5:.0f}"` is 7 in the SAME program, which no implementation should
   ever do, and which is the tell that this is a formatter path rather than a
   deliberate dialect choice.

`.2f` and the other precisions are correct for the values checked (`2.675` →
`2.67` in both, which is the binary-representation answer, not a rounding
difference), so start at how the `%.Nf`/`{:.Nf}` conversion produces its digits —
the tie case specifically.

## Gate

A `.npy` diffed against CPython: every row above via BOTH spellings
(`"%.0f" %` and the f-string), the same ties at `.1f`/`.2f`
(`0.25`, `0.35`, `1.125`, `1.135`), negatives, and `round()` of the same values
in the same file so the two paths are asserted to agree.
