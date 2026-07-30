---
track: N
prio: 60
type: bug
---

# Promotion is chosen from the LITERAL's width, so an int that grows past 2^63 wraps silently

```python
n = 1
for i in [0] * 70:
    n = n * 2
print(n)          # CPython: 1180591620717411303424     pxx: 0

n = 9223372036854775807
print(n + 1)      # CPython: 9223372036854775808        pxx: -9223372036854775808
```

Python's `int` is arbitrary precision, and [[feature-a-promotable-int]] built
exactly that (fixnum → heap bignum). It works — but only when the STATIC type
came out promotable, and that is decided by how wide the initialising literal
was.

## Measured — the boundary is the initialiser, not the arithmetic

| case | CPython | pxx |
| --- | --- | --- |
| `n = 123456789012345678901234567890; n` | correct | correct |
| `n = <big literal>; n + 1` | correct | correct |
| `n = <big literal>; n * 2` | correct | correct |
| `a, b = <two big literals>; a - b` | `1` | `1` |
| `n = <big literal>` then `n = n + n` in a loop | correct | correct |
| **`n = 1`** then `n = n * 2` seventy times | `1180591620717411303424` | **`0`** |
| **`n = 9223372036854775807`; `n + 1`** | `9223372036854775808` | **`-9223372036854775808`** |
| **`n = -9223372036854775807`; `n - 10`** | `-9223372036854775817` | **`9223372036854775799`** |
| **factorial(25) accumulated in a loop** | `15511210043330985984000000` | **prints nothing** |

So a value that STARTS big stays correct all the way, and a value that starts
small and grows wraps at 2^63 with no diagnostic. Which is the wrong way round:
the literal that overflows is the case a programmer notices, and the
accumulator is the case they do not.

The factorial row is worth a second look on its own — it produces no output at
all rather than a wrong number, which suggests something beyond a silent wrap.

## Why this is not simply "the feature is unfinished"

[[feature-a-promotable-int]] deliberately keeps loop induction variables,
indices and `len()` results as native int64 "with no checks at all" — that is a
sound performance decision and should stay. The gap is that a general-purpose
binding gets the same treatment purely because its first assigned literal fit in
a word. An accumulator is not an induction variable, and nothing distinguishes
them today.

## Options — probably wants a Track U call

1. **Default NilPy `int` bindings to promotable**, and keep native int64 only
   where the frontend can prove the range (an induction variable of a `range`
   loop, a `len()` result, an index). Correct by default, pays where it must;
   the cost lands on ordinary integer code, which is most code.
2. **Promote on overflow at run time** — keep the native representation and
   escalate the binding when an operation carries out. Needs an overflow check
   on every arithmetic op that could, and a way to re-type a live binding.
3. **Widen only when a binding is ASSIGNED FROM a promotable expression**, i.e.
   propagate promotability through the assignment graph rather than from the
   initialiser alone. Cheaper than 1, catches the accumulator, still misses
   `n = 1` growing purely by native arithmetic.

Recommendation: 1, with the proof-based exceptions the feature ticket already
names — it is the only one that makes `int` mean what Python says it means. But
it is a performance-relevant default, so file the decision rather than picking
it here.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` of the table above
against CPython's own output, and a benchmark check that ordinary integer loops
have not regressed (that is the whole cost of option 1).
