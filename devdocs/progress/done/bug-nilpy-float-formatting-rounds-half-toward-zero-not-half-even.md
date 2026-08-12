---
track: N
prio: 50
type: bug
blocked-by: []
summary: "`f\"{7.5:.0f}\"` and `\"%.0f\" % 7.5` both answer 7 where CPython answers 8: the formatter rounds a tie toward zero instead of to even, so every value whose lower candidate is ODD formats one off (1.5->1, 3.5->3, 7.5->7, -1.5->-1). The round() builtin is correct on the same values, so the two disagree with each other as well as with CPython"
status: done
owner: claude-AN
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

## 2026-08-12 — FIXED for the exact ties; a second, older family remains

`PyFmtFixed` now breaks an exact tie against the digit it is keeping (the
integer part when `prec = 0`, `fp`'s last digit otherwise) instead of asking
`Round` about the fraction alone. Every `.0f` row above now matches CPython,
and `round()` and the formatter agree.

The scaled-value shortcut was tried first and reverted: `2.675 * 100` is
*exactly* 267.5 as a double, so it manufactures a tie that is not there and
prints 2.68 where CPython prints 2.67, while `(2.675 - 2) * 100` is
67.49999999999999 and prints 2.67. The split has to stay.

**Still wrong, and NOT introduced here** — verified identical on
`stable_linux_amd64/default/pinned`:

| value | `%.1f` / `%.2f` pxx | CPython |
| --- | --- | --- |
| `0.15` | `0.2` | `0.1` |
| `0.35` | `0.4` | `0.3` |
| `0.45` | `0.4` | `0.5` |
| `1.115` | `1.12` | `1.11` |

These are *false* ties: 0.15 as a double is 0.1499999999999999944, so CPython
(which converts the exact binary value to decimal) rounds it DOWN, while
multiplying the fraction by 10 lands on exactly 1.5 and we round it as a tie.
0.45 fails the other way. Fixing them means an exact decimal conversion of the
double — the arbitrary-precision digit generation CPython and glibc use —
rather than any adjustment to the float arithmetic here, so it is a separate
piece of work. Worth its own ticket when someone picks it up; the shape is
`bug-nilpy-float-formatting-manufactures-ties-by-scaling`.

## Gate

A `.npy` diffed against CPython: every row above via BOTH spellings
(`"%.0f" %` and the f-string), the same ties at `.1f`/`.2f`
(`0.25`, `0.35`, `1.125`, `1.135`), negatives, and `round()` of the same values
in the same file so the two paths are asserted to agree.

## Log
- 2026-08-12 — resolved, commit 6e9b4d2bf.
