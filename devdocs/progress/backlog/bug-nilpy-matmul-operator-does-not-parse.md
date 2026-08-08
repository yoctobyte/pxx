---
prio: 20
track: N
type: bug
blocked-by: []
---

# The `@` matrix-multiply operator does not parse

- **Type:** bug / missing operator (NilPy) — **Track N**, but the fix is in
  Track A ground (a new `TTokenKind` in `defs.inc`)
- **Found:** 2026-08-08, sweeping the last unswept scope of
  [[feature-nilpy-arithmetic-dunders-full-protocol]]
- **Loud:** a parse error, not a wrong answer.

```python
class M:
    def __init__(self, v):
        self.v = v
    def __matmul__(self, o):
        return ("matmul", self.v, o.v)

print(M(2) @ M(5))     # CPython: ('matmul', 2, 5)
```

```
pascal26:6: error: unexpected token
  near:   M    >>>  M
```

`@` is only recognised as a DECORATOR prefix today, never as a binary operator.

## Why this is the same shape as `**=`

[[bug-nilpy-power-augmented-assign-does-not-parse]] is the sibling: both are
operators with no usable token, so the dunder plumbing has nowhere to hook. The
difference is that `**` at least exists as two `tkStar` with an ad-hoc
lookahead, while `@` has a token that means something else entirely in prefix
position. Disambiguating decorator-`@` from infix-`@` is a lexer/parser question
before it is a dunder question — which is why this is filed rather than folded
into the arithmetic-dunder ticket, whose remaining scope it was.

`__imatmul__` (`a @= b`) is in the same boat and should land with it.

## Why prio 20

`@` exists for numpy-style array code and is used essentially nowhere else. No
corpus needs it, the failure is loud, and it costs a token in Track A's shared
`defs.inc` — which is a real coordination cost for a feature nothing is waiting
on. Genuinely rainy-day-adjacent; kept in backlog only because it is the last
named gap in the arithmetic-dunder protocol.

## Gate

`.npy` diffed against CPython: `@` and `@=` dispatching `__matmul__` /
`__rmatmul__` / `__imatmul__`, a class declaring none raising TypeError, and a
control that DECORATOR `@` on the line above a def still parses — that is the
ambiguity the whole ticket is about.
