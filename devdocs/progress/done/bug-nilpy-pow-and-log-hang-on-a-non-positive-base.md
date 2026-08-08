---
prio: 55
track: N
type: bug
blocked-by: []
---

# `0 ** 0.5` HUNG — PyMathLn never terminates for a non-positive argument

- **Type:** bug (NilPy, **infinite loop**) — **Track N**
- **Found:** 2026-08-09 by a differential sweep of numeric semantics against
  CPython. Not reported by anyone; it produces no output to report.
- **Status:** done

## Measured

| expression | CPython | pxx (before) |
| --- | --- | --- |
| `0 ** 0.5` | `0.0` | **hang** |
| `0.0 ** 2.5` | `0.0` | **hang** |
| `(-8) ** (1/3)` | `(1.0000000000000002+1.7320508075688772j)` | **hang** |
| `(-2) ** 0.5` | complex | **hang** |

## Cause — one loop, read not guessed

`PyMathLn` normalises its argument with

```pascal
while m < 1.0 do begin m := m * 2.0; Dec(e); end;
```

For any `x <= 0` that condition can never become false: `0.0 * 2.0` is `0.0`
forever, and a negative doubles *away* from 1. Every fractional-exponent power
routes through it, so `0 ** 0.5` spun with no output, no diagnostic and no
progress.

## Why it rates 55 rather than the 30 its siblings got

It is an infinite loop in an utterly ordinary expression. `x ** 0.5` where `x`
happens to be 0 is not an edge case anyone writes a guard for, and the failure
gives a caller nothing at all to go on — no wrong value to notice, no exception
to catch, no partial output. A hang is the one failure mode worse than a silent
wrong answer for a batch job.

## Fix

- `PyMathLn` raises `ValueError('math domain error')` for `x <= 0`, CPython's
  own message for `math.log` of a non-positive. That protects every caller, not
  just `**`.
- `pypow_v` answers `0.0` for a zero base with a positive exponent BEFORE the
  logarithm path — CPython's answer, and the case that has to be settled early
  rather than diagnosed.
- A negative base with a fractional exponent raises a named `ValueError`.
  CPython returns a COMPLEX there and NilPy has no complex type, so a real
  number would be a wrong answer; see [[bug-nilpy-no-complex-number-type]].

Integer exponents are untouched: `(-2) ** 3` stays on the repeated-squaring
path, which is where every ordinary negative-base power lands.

## Gate
`test/test_nilpy_pow_domain.{npy,expected}` (`.expected` from CPython), driven
through a function so the operands are variants at run time rather than
constants a folder might settle: the four hangs, integer exponents both signs,
negative bases with integer exponents, `0 ** 0`, `0 ** -1` (ZeroDivisionError),
and positive fractional powers.

## Log
- 2026-08-09 — resolved, commit ebcdfe1dc.
