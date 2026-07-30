---
track: N
prio: 55
type: bug
---

# `is` on two lists compares CONTENTS, so distinct lists are "identical"

```python
a = [1]
c = [1]
print(a is c)        # CPython: False    pxx: True
print(a is not c)    # CPython: True     pxx: False
```

`is` must be identity, always. User objects and dicts are correct
(`K(1) is K(1)` and `{"x":1} is {"x":1}` both False), so it is specifically
the list arm that routes through the value comparison — presumably the same
`pylist_eq` path `==` uses ([[bug-a-nilpy-container-equality-compares-identity]]
taught `==` to compare contents, and `is` appears to have been swept along).

Silent, and it inverts the one thing `is` is for: distinguishing two equal
values that are different objects. `if a is not c:` — the standard guard before
mutating a caller's list — takes the wrong branch.

Found by sweeping identity/ternary/unpacking/mutable-default constructs against
CPython; the rest of that sweep matched, including `is None` / `is not None`,
aliasing (`b = a; a is b` True), the conditional expression, tuple unpacking
and the `acc=None` mutable-default idiom.

## Gate

`make test-nilpy` + self-host byte-identical, plus `is` / `is not` over equal
lists, aliased lists, dicts, user objects, strings, small ints and None.

## Log
- 2026-07-30 — resolved, commit e164d2619.
