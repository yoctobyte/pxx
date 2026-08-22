---
track: A
prio: 20
type: compat
blocked-by: []
summary: "`--strict-fpc` reproduces FPC's shift widths but not its `Abs`/`Sqr` widths, so `Abs(Low(Integer))` and `Sqr(65536)` keep the native-width answer under the flag. Completes the strict-mode escape hatch the shift decision promised."
status: backlog
---

# `--strict-fpc` does not reproduce FPC's `Abs` / `Sqr` widths

Found 2026-08-22 by an FPC differential sweep over ordinal arithmetic
(`fpc -Mobjfpc -O1` 3.2.2 vs pxx `80bbe2f38`).

Exactly the shape of [[bug-a-strict-fpc-does-not-reproduce-fpc-shift-widths]],
one operator family later: the **default** dialect divergence is deliberate and
documented (`devdocs/dev/pascal-dialect-divergences.md`, the `Abs`/`Sqr`
section) — shifts and these two both evaluate at native width and do not
truncate to the operand's declared type. What is missing is the strict-mode
escape hatch, so someone porting FPC bit-twiddling can pin shift width with the
flag but silently cannot pin these.

## The measurement

`i: Integer`. Third column is the flag that should have changed the answer.

| expression | FPC | pxx default | pxx `--strict-fpc` |
| --- | --- | --- | --- |
| `Abs(i)`, `i = Low(Integer)` | -2147483648 | 2147483648 | **2147483648** |
| `Sqr(i)`, `i = Low(Integer)` | 0 | 4611686018427387904 | **4611686018427387904** |
| `Sqr(i)`, `i = 65536` | 0 | 4294967296 | **4294967296** |

Unaffected and must stay unaffected: `i * i` (widens in both), `-i` (widens in
both), `Abs(SmallInt)` (promotes to Integer in both), `Abs(Int64)` (wraps in
both). Only the exactly-32-bit `Abs`/`Sqr` case moves.

## What strict mode has to reproduce

FPC's rule for both is "result keeps the argument's type, after the usual
promotion of anything narrower than Integer". So under `StrictShiftWidth`'s
sibling flag:

- `Abs(x)` where `x` is a declared 32-bit signed type: compute at 32 bits, so
  `Abs(Low(Integer))` is `Low(Integer)` again.
- `Sqr(x)` likewise: a 32-bit multiply that wraps, which is why FPC answers 0
  for both rows above.

Note the wart being copied — `i * i` widens but `Sqr(i)` does not, though they
denote the same product. That is the same "explicitly copy their bugs" clause
the shift decision spelled out, so reproduce it rather than rationalising it.

## Where the code is

`Abs` and `Sqr` are builtin calls, not binops, so this is **not** the shift
arm that `StrictShiftWidth` already gates — expect a different site. Find where
the builtin's result type is assigned (the same place that already promotes
`Abs(SmallInt)` to Integer, since that row agrees with FPC) and make it keep the
argument's type under the flag, then let the existing narrow-back do the rest.
Whether this earns its own flag name or joins `StrictShiftWidth` under the
`--strict-fpc` umbrella is a judgement call; prefer joining, since a caller who
wants one almost certainly wants both.

## Prio

20. This is parity for a mode that exists to copy FPC's warts, and the default
dialect is already correct and documented. Below the compat work whose subject
is compiling real-world code.

## Gate

Every row above matching `fpc -O1` under `--strict-fpc`, the default dialect
unchanged, and self-host byte-identical.
