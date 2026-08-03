---
track: N
prio: 30
type: bug
status: done
owner: claude-AN
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

## Fixed 2026-08-03 — it was not a parse bug, and prio 30 was based on a wrong premise

**Root cause: Pascal's `E is TClass` TYPE test, in the shared `ParseExpr`,
claimed `is <ClassName>` before NilPy's identity `is` ever saw it.** The
intercept (parser.inc, the `is`/`as` branch and its class-reference-value
sibling) had no `PyExprMode` gate, so under NilPy:

```python
k1 = K(1)
print(k1 is K(2))      # CPython: ctor 2 / False     pxx: (no ctor) / True
```

The construction on the right **never ran**, the trailing `(2)` was left
behind, and the answer was `True` — because `k1` really is a `K`, which is
what the Pascal type test asks. Not a parse failure: a **silent wrong
answer**, at module scope. Inside a `def` the leftover tokens surfaced as
"expected newline after statement", which is the recon's "two distinct failure
shapes" — one bug, two symptoms, depending on whether the enclosing scope
tolerated the orphaned `(2)`.

`is not` was unaffected (the Pascal pattern does not match it), and that
asymmetry is what made the two shapes look unrelated.

### Why the ticket's own reproducer could not see it

`X() is Y()` is always `False` in Python **and** was False under the bug, so a
boolean-only test is blind here. It was found by giving `__init__` a `print`
and counting constructor calls — the missing `ctor 2` line is the whole
finding. The gate test asserts those lines for that reason.

That also disposes of the prio-30 rationale ("`X() is Y()` is always False and
so is a rare thing to write"). The reachable form is the ordinary
`x is SomeClass(...)`, and it answered wrongly rather than failing.

### The fix

Gate both Pascal is-test intercepts on `not PyExprMode`. Python's type test is
`isinstance`, which has its own branch, so NilPy loses nothing. `as` is left
exactly as it was (Python has no `as` expression operator, so gating it would
have been an unmeasured change).

Pascal is untouched, and the self-host fixedpoint proves it: the compiler is
Pascal source and leans on `is` heavily, and it still reproduces itself
byte-identically.

### A second, unrelated bug found on the way and fixed here

`r = K(1) == k2` and `r = K(1) in [k1]` also failed ("expected expression"),
and `r = K(1) is k2` gave "undefined variable (is)" — a **left**-operand
failure, mirroring the ticket's right-operand one. Cause: the statement-level
construction fast-path claimed the RHS on its OPENING shape alone (class name
+ `(`, minus the `.method(` case) without checking the construction ENDED the
right-hand side — the "a fast-path beside a real expression path is a second
parser that disagrees silently" pattern this repo has hit repeatedly. New
`PyCtorEndsRhs` requires a statement terminator after the ctor's `)`, so
`x = C(1)` keeps the fast path and `x = C(1) <anything>` goes to the
expression parser.

### Verified

`test/test_nilpy_is_identity_vs_class_test.npy` (new, registered in both
`test-nilpy` Makefile sites), byte-identical to CPython including every
constructor-call line: `is` with a construction on the right, `is not`, both
sides constructed, nested in a call / parens / a list literal, at statement
level, a genuinely-True identity, a different class on the right (identity,
not a type test), and `==` still constructing. `tools/gate.sh quick` GREEN.

## Log
- 2026-08-03 — resolved, commit 94971ff0b.
