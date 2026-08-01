---
summary: "NilPy: a BOOL operand is not treated as an int — it bypasses the mixed-type TypeError guard vs containers AND forces UNSIGNED arithmetic, so `True // -7` prints 18446744073709551615"
type: bug
track: N
prio: 60
---

# `bool` operand is not treated as an int — two silent-wrong faces

- **Type:** bug (NilPy semantics, silent wrong value) — **Track N**
- **Opened:** 2026-08-01, from the CPython differential sweep (1094 cases,
  self-hosted binary at `3f2c5b915`).

## The contrast that isolates it

Same operators, same right-hand operand, same CPython oracle (`TypeError` for
every one). Only the left operand's type differs:

| left operand | cases diverging |
| --- | --- |
| `7` (int) | **0 / 13** — all correctly raise `TypeError` |
| `True` (bool) | **8 / 13** — silently compute on the list handle |

So the guard exists and works; it just does not classify `bool` as a number.

## Measured

| expression | CPython | pxx |
| --- | --- | --- |
| `True - [1, 2]` | `TypeError` | **`-1824522263`** |
| `True / [1, 2]` | `TypeError` | **`0.000000000000007`** |
| `True // [1, 2]` | `TypeError` | **`0`** |
| `True % [1, 2]` | `TypeError` | **`1`** |
| `True < [1, 2]` | `TypeError` | **`True`** |
| `True <= [1, 2]` | `TypeError` | **`True`** |
| `True > [1, 2]` | `TypeError` | **`False`** |
| `True >= [1, 2]` | `TypeError` | **`False`** |

`True + [1,2]`, `True * [1,2]`, `True ** [1,2]`, `True == [1,2]` and
`True != [1,2]` already agree with CPython — note `==`/`!=` are *supposed* to be
`False`/`True` rather than an error, so those are correct, not lucky.

## Why it matters

The four ORDERING rows are the worst: they return a clean `True`/`False` from a
pointer comparison. Nothing about the output suggests a type error occurred, so
a condition silently takes a branch decided by an allocation address.

## Face 2 — a bool operand forces UNSIGNED arithmetic

Found in the same sweep, and almost certainly the same root cause. With a
NEGATIVE right operand the result comes back as unsigned 64-bit:

| expression | CPython | pxx |
| --- | --- | --- |
| `True // -7` | `-1` | **`18446744073709551615`** (2⁶⁴−1) |
| `True % -7` | `-6` | **`18446744073709551610`** (2⁶⁴−6) |

Again isolated by the same contrast: `7 // -7` and `7 % -7` do **not** diverge.
So an int operand keeps signed semantics and a bool operand does not — the
result type is being taken from the bool's own (unsigned/byte-ish) type-kind
rather than promoted to a signed integer.

This is the more alarming of the two faces: the value is not merely wrong, it is
wrong in a way that looks like a plausible huge positive number, and it survives
into any later arithmetic or comparison.

## Cause (to confirm before fixing)

`test_nilpy_mixed_type_operands` already asserts `sub-list TypeError` and
`mul-dict TypeError`, so the clash detection is real and covers int-vs-container.
The likely gap is that the predicate deciding "this operand is a number" tests a
specific integer type-kind set that omits `tyBoolean` — cf. `IRPyNumStrClash`
(`compiler/ir.inc:3841`), which is documented as firing only for a
str-vs-number PAIR. **Measure before concluding**: dump the inferred kinds with
`PXXDBG` rather than assuming which predicate is short.

In Python `bool` IS a subclass of `int` (`True + 1 == 2`), so the fix direction
is "treat `tyBoolean` as a number everywhere the guard already treats an int as
one" — not a bool-specific special case. Check the same hole for
`bool` vs `dict`/`bytes`/`str`, and for a bool on the RIGHT
(`[1,2] - True`), none of which this sweep isolated separately.

Both faces point at one predicate: **`tyBoolean` is not in the set that means
"an integer"**. In Python `bool` IS a subclass of `int`, so fixing that one
classification should close the container-guard hole and the signedness hole
together. Verify that it does rather than patching them separately — if one
survives, they were two bugs after all and the second needs its own repro.

## Gate

`make test-nilpy` + self-host byte-identical, plus BOTH tables above added to
`test_nilpy_mixed_type_operands` (which is where the int-vs-container cases
already live) with CPython's own output as the expectation — and a check that
`True + 1 == 2` and the `==`/`!=` rows above are unchanged. Sweep the bool cases
against the CPython oracle afterwards, not just the listed rows: the sweep found
these by matrix, and a partial fix would leave a neighbour wrong.
