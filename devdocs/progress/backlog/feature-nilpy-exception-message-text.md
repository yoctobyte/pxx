---
track: N
prio: 30
type: feature
---

# NilPy: exception message text — super().__init__(msg) discarded, str(e) empty

## Gap

`print(f"ERROR: {e}")` on a caught exception prints an EMPTY message.
Two missing pieces:

1. `super().__init__(f"THROW {code}")` in a user exception ctor is consumed
   and DISCARDED (pyparser ~6189, deliberate v1 stub) — the message never
   lands anywhere.
2. Formatting an exception object (`{e}` / `str(e)`) has no route to a
   message field even if one were stored.

## Impact

uforth's include-error context lines print `ERROR: ` with no detail, where
CPython prints `ERROR: <file>:<line>: THROW -13 (line: '...') ...`. This is
the ONLY remaining diff in the Forth-2012 filetest run — all test results
are byte-identical to CPython; only this final error-message text differs.
Cosmetic for the suite, but any Python code that stringifies exceptions
loses the message.

## Sketch

Give the pylib Exception base a message field (str), make
`super().__init__(expr)` in a class whose base chain reaches Exception
store the evaluated expr there, and route str(e)/f-string interpolation of
a class value whose class derives Exception to that field. `raise
X.Create(msg)` already carries a message — check how the except-binding
exposes it today.
