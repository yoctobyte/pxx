---
track: N
prio: 30
type: bug
blocked-by: []
summary: "`zip(*rows)` — the transpose idiom — and `g(*xs)` where g is a bound method held in a variable both fail to parse (\"expected expression\"), while `f(*xs)` into a user def, `print(*xs)` and `max(*xs)` all work. The star expansion is wired per call-path, and two paths were left out."
---

# `zip(*m)` and `bound(*xs)` are refused

```python
m = [[1, 2], [3, 4]]
print(list(zip(*m)))              # CPython [(1, 3), (2, 4)]
                                  # pascal26: error: expected expression   near: list zip >>> matrix

g = K().g
print(g(*xs))                     # CPython works; pxx: same parse error
print(sum(*[[1, 2]]))             # CPython 3;     pxx: same parse error
```

Measured 2026-08-15, sweeping star-unpack across call shapes. What DOES work:

| call shape | `*xs` |
| --- | --- |
| user def — `f(*xs)` | works |
| `print(*xs)` | works |
| `max(*xs)` | works |
| `zip(*m)` | **refused** |
| `sum(*xs)` | **refused** |
| bound method in a variable — `g(*xs)` | **refused** |

Loud in every failing case, and the message is the generic "expected
expression" pointing at the operand — it names neither the star nor the callee,
so it reads as a syntax error in the caller's own code.

## Why it is worth more than its loudness suggests

`zip(*rows)` is THE transpose idiom; it is how a matrix is flipped, how columns
are named, and how `dict(zip(*pairs))` is written. It is far more common in real
Python than the general `f(*args)` forwarding that already works.

## Cause, as far as the sweep shows

`*` expansion is attached to individual call paths — `PyStarForwardCall` /
`PyPackStarArgs` for a def, and the special-cased builtin arms — rather than to
one argument-parsing routine. `zip` is parsed by its OWN header lowering
(`PyParseForZip` / `PyMakeZip`), which never learned about a star; `sum` and a
bound-method-in-a-variable go through paths that likewise parse arguments
themselves. This is the same "one construct, N argument loops" shape that
[[bug-nilpy-bare-genexpr-as-a-method-argument-does-not-parse]] found one probe
earlier — the bare genexpr has exactly the same list of haves and have-nots,
which is the strong hint that BOTH want one shared "parse a NilPy call argument"
entry point rather than a third and fourth copy of the diversion.

## Gate

`.npy` diffed against CPython: `zip(*m)` (two and three rows), `dict(zip(*p))`,
`sum(*[xs])`, a bound method, a method on a class instance, a user def, `print`,
`max`/`min`, and a star ALONGSIDE fixed arguments where CPython allows it.
