---
track: N
prio: 55
type: bug
owner: unassigned
blocked-by: []
summary: "`H().fn(1, b=2)` and `hs[0].fn(1, b=2)` are `error: undefined variable (b)` where `h.fn(1, b=2)` and `g().fn(1, b=2)` answer correctly — a KEYWORD argument to a callable FIELD, only when the receiver is a constructor call or a subscript. The keyword name parses as an expression, the same symptom the statically-unknown-callee ticket had."
---

# A keyword argument through a procedural field needs a plain receiver

```python
def named(a, b=10):
    return a + b

class H:
    def __init__(self):
        self.fn = named
```

| call | pxx | CPython |
| --- | --- | --- |
| `h = H(); h.fn(1, b=2)` | 3 | 3 |
| `def g(): return H()` then `g().fn(1, b=2)` | 3 | 3 |
| `H().fn(1, b=2)` | **`error: undefined variable (b)`** | 3 |
| `hs = [H()]; hs[0].fn(1, b=2)` | **`error: undefined variable (b)`** | 3 |
| all four of the above with POSITIONAL args | 3 | 3 |

So it is not "a fresh receiver" — a call RESULT is fine. It is a **constructor
call** or a **subscript** as the receiver, and only with a keyword argument.

## Found by

The sibling sweep of
[[bug-n-a-field-assigned-a-module-level-def-has-no-inferable-type]], which made
`obj.fn(...)` on a statically-typed receiver resolve at all. Before that fix
every cell in the table failed with `H has no method .fn()`, so this
combination has never worked and is not a regression — three of the four cells
now do, and this is the fourth.

## Why it is filed rather than folded in

The symptom — a keyword NAME parsed as an ordinary expression identifier — is
exactly the one
[[bug-nilpy-a-keyword-call-through-a-statically-unknown-callee-does-not-compile]]
reported, and that ticket's own guidance is the right frame here too:

> That decision should depend on the SYNTAX (an identifier followed by `=` at
> argument level is always a keyword argument in Python), not on whether a
> candidate callee was resolved.

`PyMakeVariantFieldCall` parses its arguments with a bare `ParseArgExpr` loop
and has no keyword handling of its own, so the two cells that DO work are
reaching keyword support from their surrounding context rather than from the
builder. Fixing the builder is likely the whole job — but it is a change to
argument parsing shared by every callable-field call, which is a different
blast radius from the field-typing fix it was found under, and deserves its own
gate rather than riding along.

## Gate

All four receiver spellings above, positional and keyword, plus a field rebound
to a different function (the reason the field carries no static signature), plus
`test_nilpy_callable_field_all_shapes` and `test_nilpy_field_holding_a_def`
green.
