---
track: N
prio: 60
type: bug
---

# NilPy: any statement after a `for` inside a def failed to parse

Found 2026-07-20 driving uforth (wall 476). Pre-existing, not introduced by the
one-line-suite work that surfaced it.

```python
def f() -> int:
    y = 0
    for s in [1, 2]:
        y = y + s
    return y          # "expected newline after statement"
```

## Root cause

`PyParseBlock` decides whether a statement consumed its own indented block by
matching the returned node's KIND against
`[AN_IF, AN_WHILE, AN_FOR, AN_TRY_EXCEPT, AN_TRY_FINALLY]`. A desugared `for`
does not return any of those: `PyParseFor` builds init statements plus a while
and returns the `AN_SEQ` that chains them. So the check missed it, the parser
then demanded a newline it had already consumed, and the next statement — of
ANY kind, not just `return` — was rejected.

## Why it went unnoticed

`for` at MODULE scope goes through a different statement loop, and the existing
.npy tests exercise it there. uforth is the first corpus with for-loops inside
methods that have code after them.

## Fix

`PyParseFor` sets `PyStmtAteBlock`, the flag nested defs already use to say
exactly this ("I consumed my own block and its DEDENT"). Matching on a flag
rather than a node kind is what the mechanism is for — a desugaring is free to
return whatever node shape it likes.

Covered by `test/test_nilpy_stmt_after_for.npy` (statement after a for, `return`
from inside a for, and nested for-loops), diffed against CPython and in the
`test-nilpy` gate.
