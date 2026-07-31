---
track: N
prio: 45
type: bug
---

# `0 or "x"` returns True — a mixed str/number `and`/`or` yields a bool instead of the operand

```python
print(0 or "x")      # CPython: x      pxx: True
print(1 or "x")      # CPython: 1      pxx: True
print("" or 5)       # CPython: 5      pxx: True
print(0 and "x")     # CPython: 0      pxx: False
```

[[decide-nilpy-and-or-return-operand-or-bool]] settled that `and`/`or` return
the OPERAND, and they do — except for one operand-type pair.

## Boundary — only str-vs-number

| expression | CPython | pxx |
| --- | --- | --- |
| `0 or 5` | `5` | `5` ✓ |
| `[] or "x"` | `x` | `x` ✓ |
| `None or "x"` | `x` | `x` ✓ |
| `"a" or "b"` | `a` | `a` ✓ |
| **`0 or "x"`** | `x` | **`True`** |
| **`1 or "x"`** | `1` | **`True`** |
| **`"" or 5`** | `5` | **`True`** |
| **`0.0 or "x"`** | `x` | **`True`** |
| **`0 and "x"`** | `0` | **`False`** |
| `if 0 or "x":` (condition context) | truthy | truthy ✓ |

The same axis as [[bug-nilpy-mixed-type-arithmetic-silently-does-pointer-math]]:
a str paired with a number.

## This is a KNOWN trade-off whose premise is now falsified

`pyparser.inc`, `PyBoolOpArmsCompatible`, says so explicitly:

> MIXED kinds — a string and a Boolean — keep the boolean lowering, because
> typing that ternary as either arm's type reinterprets the other one (a Boolean
> read as a string pointer SEGFAULTS, which is how this rule was found). ...
> what is lost is only the VALUE identity of a mixed-type `or`, **and that shape
> does not occur outside a condition**.

The predicted loss is exactly what is measured above, so the analysis was right.
The justification is the part that does not hold: `print(0 or "x")` is that
shape outside a condition, and it is ordinary Python (`name = arg or "default"`
is the idiom, and it mixes types whenever the default is a different type from
the value).

## Shape of a fix

Do NOT type the ternary as either arm — that is the segfault the comment
records. `PyMakeBoolOpValue` already has a `tyVariant` fallback for its result
type; the blocker is one function earlier, `PyBoolOpArmsCompatible`, which
returns False for a mixed pair so the VALUE lowering is never chosen at all.
Admitting the str-vs-number pair there, and letting the existing `else
ASTTk[node] := Ord(tyVariant)` branch carry it, boxes each arm instead of
reinterpreting it.

That is plausible now in a way it may not have been when the rule was written —
variant boxing of a ternary arm has since been made to work (the
conditional-expression lowering handles class/variant arms). Verify against the
original crash: a `string and Boolean` pair in a condition, which is the case
the comment names.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` of the table above
against CPython's own output, and specifically a mixed `or` used AS A CONDITION
(`if 0 or "x":`) to confirm the truthiness path is unchanged.

## Log
- 2026-07-31 — resolved, commit 83ef062fcea265fd31239a08bd739546abfa0234.
