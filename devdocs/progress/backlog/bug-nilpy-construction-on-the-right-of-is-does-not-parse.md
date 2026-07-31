---
track: N
prio: 30
type: bug
---

# A construction on the right of `is` does not parse

```python
print(K(1) is K(1))
```

```
Expected: ), but got:  (Kind: 74, Line: N)
error: unexpected token
```

Bound to names first it is fine, and answers correctly:

```python
k1 = K(1)
k2 = K(1)
print(k1 is k2)      # False, matching CPython
```

So this is the parse of the RIGHT operand only — `is` reaches `PyParseBitOr`
for it, and a construction is evidently not reachable from there in this
position. `is not` presumably behaves the same; a call on the right
(`x is f()`) is worth checking in the same pass.

Found while gating [[bug-nilpy-is-on-two-lists-compares-contents]], whose own
subject (identity vs contents) is fixed — the reproducer for it had to be
rewritten to bind the operands to names first, which is what exposed this.

Low priority: `X() is Y()` is always False in Python and so is a rare thing to
write. It is filed because a parse error on a legal expression is a wall
somebody will hit from generated or transliterated code.

## Recon 2026-07-31 — narrower repro found; TWO distinct failure shapes, not fixed

Measured (not assumed) with `-g`/temporary tracing rather than guessed at.
`PyParseIsCmp` (pyparser.inc) calls `PyParseBitOr` for BOTH operands of `is`,
and `PyParseBitOr`'s own chain (`PyParseBitXor` → `PyParseBitAnd` →
`PyParseShift` → `PyParseBitOperand` → the shared Pascal `ParseExpr`) is where
a NilPy class construction is ultimately recognised (deep in
`ParseFactorCore`, parser.inc). It is the exact SAME call for the left operand
and the right — no `is`-specific branch sits between `Next` (past `is`) and
`PyParseBitOr;` besides the `PyBareNoneHere` check for a literal `None` — so
there is no obvious reason the identical chain would recognise a constructor
on the left and not on the right.

And empirically it is NOT one clean symptom:

- `print(K(1) is K(1))` (inside a call's argument list — the ticket's own
  repro): fails at `Expected: ), but got: tkLParen` — i.e. the right-hand
  `PyParseBitOr` call stops after consuming the bare identifier `K`, leaving
  `(1)` unconsumed, and print()'s own closing-paren check then trips on it.
- `r = K(1) is K(1)` (a bare statement-level assignment, no enclosing call):
  a DIFFERENT error, `undefined variable (is)` — meaning at STATEMENT level
  the RHS parse does not appear to reach `PyParseIsCmp`/the `is` keyword at
  all; something stops after the left `K(1)` and then chokes on the literal
  token `is` as if it were an identifier reference. This suggests statement-
  level assignment RHS parsing may take a different entry point than the
  call-argument path for at least some shapes, which was not expected going
  in and needs to be understood before touching the shared precedence-chain
  code near `PyParseIsCmp`/`ParseFactorCore` — both are shared with every
  other frontend (Pascal, C) and are the same fragile ground flagged
  elsewhere in this repo's own dev docs.

Not fixed this pass: still genuinely low priority (`X() is Y()` is always
`False` in Python) and the two-shapes finding means a five-minute "the RHS
just needs the same lookahead the LHS gets" patch would likely be wrong or
incomplete. Left for a dedicated pass with real `-g`/gdb tracing of BOTH
shapes rather than another round of read-the-source guessing.

## Gate

`make test-nilpy` plus `is` / `is not` with a construction, a call and a
subscript on the right, diffed against CPython.
