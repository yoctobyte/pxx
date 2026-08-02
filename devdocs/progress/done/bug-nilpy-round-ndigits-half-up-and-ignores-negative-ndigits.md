---
track: N
prio: 60
type: bug
---

# `round(x, n)`: negative n ignored, and ties went half-up

- **Type:** bug (NilPy, silent wrong value) — **Track N**
- **Found and PARTIALLY FIXED:** 2026-08-02, by a differential sweep against the
  CPython oracle (`tools/pydiff.py`).

## Measured

| expression | CPython | pxx before | pxx after |
| --- | --- | --- | --- |
| `round(1234.5678, -2)` | `1200.0` | **`1235.0`** | `1200.0` |
| `round(2.5, 0)` | `2.0` | **`3.0`** | `2.0` |
| `round(0.125, 2)` | `0.12` | **`0.13`** | `0.12` |
| `round(2.675, 2)` | `2.67` | **`2.68`** | **`2.68`** |
| `round(2.665, 2)` | `2.67` | `2.67` | **`2.66`** |

The no-`ndigits` form (`round(0.5)`, `round(1.5)`, …) was correct throughout.

## Two real bugs, both fixed

1. **Negative `n` was ignored.** `for i := 1 to n do scale := scale * 10.0`
   simply does not run when `n < 0`, so `scale` stayed `1.0` and
   `round(1234.5678, -2)` returned `1235.0` — wrong by two orders of magnitude,
   silently. Now scales by dividing instead (and multiplies back), rather than
   building a fractional scale and dividing by it: `1/100` is not exact and
   `r/0.01` comes back `1199.9999…`.

2. **Ties went half-up.** Python's rule is half-to-EVEN. Fixed.

## What is STILL wrong, and why it is not fixable here

`round(2.675, 2)` still gives `2.68`, and `round(2.665, 2)` moved from
accidentally-right to wrong. That is an honest loss on one case and it is
recorded rather than glossed: half-up happened to match CPython on `2.665`.

The cause is not precision drift — I checked, and it is not:

```
2.675 * 100  ==  267.5     exactly, in BOTH CPython and pxx
2.665 * 100  ==  266.5     exactly, in BOTH
```

CPython does not scale. `round(x, n)` rounds the **exact decimal value of the
double**:

```
Decimal(2.675) = 2.67499999999999982236431605997495353221893310546875   -> 2.67
Decimal(2.665) = 2.66500000000000003552713678800500929355621337890625  -> 2.67
```

One is just below the tie, the other just above. Multiplying by 100 collapses
both to exactly `x.5` and destroys the very information that decides them, so
**no tie-breaking rule applied to the scaled value can be right** — half-up gets
`2.665` by luck and `2.675` wrong; half-even gets the genuine ties right and
both of these wrong.

Matching CPython requires correctly-rounded decimal conversion of the double —
the same primitive blocked by
[[bug-b-floattostrsig-caps-at-15-significant-digits]], which needs exact digit
generation (bignum over the 53-bit mantissa, or Grisu/Ryu). Rounding a
17-significant-digit string is NOT enough: `2.665` renders as exactly
`2.6650000000000000` at 17 digits, which is ambiguous at the tie.

So `round()` parity and float-repr parity want the same RTL capability. Noted on
both tickets.

## Landed anyway because the rule is now right

Three genuine defects fixed (negative `ndigits`, and half-even at `2.5` and
`0.125`) against one case that stops being accidentally right. The scaled-value
tie-break is now the CORRECT rule; what remains is attributable to a different,
filed bug rather than to this code.

## Verified

`test/test_nilpy_round.npy`, wired into `make test-nilpy`, asserting pxx's
current behaviour with the two known-divergent cases called out in comments so
nobody "fixes" the expectation instead of the RTL.
