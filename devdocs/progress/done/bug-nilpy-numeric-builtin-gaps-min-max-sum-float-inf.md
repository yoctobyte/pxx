---
track: N
prio: 50
type: bug
---

# Numeric builtin gaps: `float("inf")`, variadic `min`/`max`, `sum(x, start)`

- **Type:** bug (missing/incorrect builtins — all loud) — **Track N**
- **Found and FIXED:** 2026-08-02, by a differential sweep against the CPython
  oracle.

## Measured

| expression | CPython | pxx before |
| --- | --- | --- |
| `float("inf")` | `inf` | **`ValueError: could not convert string to float`** |
| `float("-inf")`, `float("Infinity")`, `float("nan")` | ditto | ditto |
| `min(3, 1, 2)` | `1` | **`no overload of min matches these arguments`** |
| `max(3, 1, 2)` | `3` | ditto |
| `sum([1,2,3], 10)` | `16` | **`no overload of sum matches these arguments`** |

`float("inf")` is the one that matters most: it is how you spell an unbounded
sentinel, and `best = float("inf")` before a minimisation loop is everywhere.

## Fixes

**`float()` special spellings.** `inf` / `infinity` / `nan`, case-insensitive,
with an optional sign, checked before the digit scan (which has no notion of
them). No literal spells these values, so they are built by overflow —
`1e308 * 10` is `+Inf`, `Inf - Inf` is `NaN` — after verifying on this target
that those PRODUCE the values rather than trapping (float exceptions are masked;
see `feature-float-exception-mask-control`).

**Variadic `min`/`max`.** Three- and four-argument overloads, each folding the
existing two-argument form, which already does the `pyvar_gt` content
comparison. Five or more still fails; that wants a genuinely variadic path
rather than another overload, and is not worth guessing at until something needs
it.

**`sum(iterable, start)`.** The optional initial accumulator, one overload over
the existing loop.

## Verified

`test/test_nilpy_numeric_builtins.npy`, wired into `make test-nilpy`,
byte-identical to CPython. Covers all four `inf`/`nan` spellings plus case and
sign variants, `nan != nan`, ordinary `float()` parses and its `ValueError`
path, 2/3/4-argument `min`/`max`, the single-iterable forms, `sum` with and
without a start (including over an empty list), and mixed int/float and string
comparands.

## Context: the rest of the numeric surface is CLEAN

Same sweep, all agreeing with CPython: negative floor division (`-7 // 2`),
modulo sign rules on both operands (`-7 % 3`, `7 % -3`), `divmod` with
negatives, `**` including negative bases, `int()` truncation toward zero,
true division, `bool` arithmetic, `2**40` and both `2**31` boundaries, and all
six bitwise/shift operators including negative shifts.

## Still divergent, and NOT fixed here

`print(1e-10)` gives `0.0000000001` where CPython gives `1e-10` — CPython
switches to exponent form below `1e-4`. That is the float-repr family, blocked
on [[bug-b-floattostrsig-caps-at-15-significant-digits]]; recorded on
[[bug-nilpy-float-repr-not-shortest-roundtrip]].
