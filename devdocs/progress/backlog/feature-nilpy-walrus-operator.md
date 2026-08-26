---
track: N
prio: 35
type: feature
---

# `:=` (walrus) — the assignment expression is not parsed

```python
xs = [1, 2, 3, 4]
if (n := len(xs)) > 3:
    print("big", n)
```

```
pascal26:2: error: undefined variable (n)
```

The name is never bound, so the failure is a clean "undefined variable" at the
USE — visible, not silent.

**2 of the neuzelaar corpus's 168 files**, which is why this sits low. It is
listed here so the census in `feature-nilpy-thirdparty-libraries-as-targets` has
a ticket behind every line rather than one unaccounted construct.

## Notes

`:=` is Pascal's ASSIGNMENT token, so the token already exists — this is about
NilPy's expression parser accepting a binding in expression position and
registering the name in the enclosing scope (Python scopes a walrus to the
enclosing function/module, NOT to the comprehension or `if` it appears in).

The three shapes real code uses: an `if`/`while` condition (above), a
comprehension filter (`[y for x in xs if (y := f(x)) is not None]`), and inside
a call argument.

## Gate

`make test-nilpy` + self-host byte-identical, with a CPython-diffed test over
all three shapes plus the scoping rule (the name is still bound AFTER the
statement).
