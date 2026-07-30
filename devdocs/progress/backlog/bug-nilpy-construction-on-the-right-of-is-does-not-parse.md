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

## Gate

`make test-nilpy` plus `is` / `is not` with a construction, a call and a
subscript on the right, diffed against CPython.
