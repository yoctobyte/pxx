---
prio: 20
track: N
type: bug
blocked-by: []
status: done
owner: claude-AN
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

## Resolved 2026-08-15

Fixed. **The ticket's stated coordination cost was wrong**: `tkAt` already
exists in `defs.inc` and `pylexer.inc` already emits it for `@` — infix `@`
needed no new token at all, only a parser arm. The one token appended is
`tkAtEq`, for `@=`, exactly as `**=` needed `tkPowEq` (a two-char augmented
spelling has to lex as ONE token or `a @= b` reads as `a @ (= b)`). Appended at
the tail; no ordinal moved.

The decorator ambiguity the ticket is named for turned out not to be one:
decorator-`@` is consumed at STATEMENT START, before any expression is parsed,
so an infix arm in `ParseTerm` cannot see it. `@property` / `@staticmethod` on
the line above a `def` are asserted in the test as the control.

- `compiler/defs.inc` — `tkAtEq` appended after `tkPowEq`.
- `compiler/pylexer.inc` — `@` lexes `@=` as `tkAtEq`.
- `compiler/parser.inc` — `ParseTerm` accepts `tkAt` at multiplicative
  precedence in `PyExprMode` only (it is Pascal's address-of prefix otherwise),
  and dispatches `__matmul__` -> `__rmatmul__` -> TypeError. Never an
  `AN_BINOP`: no builtin type implements `@`, so there is no arithmetic meaning
  to fall through to. `PyReflName` gained `__rmatmul__`.
- `compiler/pyparser.inc` — `PyAugBinTok(tkAtEq) = tkAt`,
  `PyAugDunderName` gained `__imatmul__`/`__matmul__`, both augmented-assign
  sites (bare name and lhs-expression) raise for a non-dunder target instead of
  building the meaningless binop, and the three aug-token scan lists plus the
  lambda-body re-speller learned `@=`.

Gate: `test/test_nilpy_matmul_dunder.npy` byte-identical to CPython — `__matmul__`,
`__rmatmul__`, `@=` on a bare name AND on a field, `__imatmul__` with the
`__matmul__` rebind fallback, `1 @ 2` raising TypeError, and the decorator
control. `gate.sh quick` GREEN (self-host fixedpoint + testmgr quick + FPC seed).

Not in scope, found while testing: a USER-DEFINED decorator (`@deco` where
`deco` is an ordinary function) is still refused — "unsupported decorator (only
@dataclass and @overload)". Unrelated to `@` the operator; filed separately.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
