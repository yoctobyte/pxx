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

---

## 2026-09-11, frankB — it is a CORPUS wall, plus two rows this ticket did not have

Measured at compiler `73219e9ca3b7`. I nearly filed this a second time under a
WRONG generalisation; `tools/progress.sh check`'s NEAR-DUP row is what stopped
it, and the correction is worth recording because the wrong framing is the
tempting one.

**I had it as "a callable FIELD does not take keywords, while a variable, a dict
value and a list element do".** That is false, and this ticket's title had it
right all along: the field is not the discriminator, the RECEIVER EXPRESSION is.
One callable field, five receiver shapes:

| receiver | `obj.b(room=2, laden=5)` |
| --- | --- |
| a plain name, `h.b(...)` | **correct** — `('made', 5, 2)` |
| a function call, `g().b(...)` | **correct** |
| a list subscript, `hs[0].b(...)` | `error: undefined variable (room)` |
| a dict subscript, `hd['k'].b(...)` | `error: undefined variable (room)` |
| a constructor call, `K(make).b(...)` | `error: undefined variable (room)` |

The dict-subscript row is new here; the ticket named a subscript without saying
which, and both spellings refuse. Written OUT of declaration order on purpose —
`b(laden=5, room=2)` and `b(5, 2)` agree, so an in-order row cannot tell a
working door from one that merely drops the names.

### It is a corpus wall now

`lekkerzeilen/traffic.py:375`, and it is the real remaining wall in that module:

```python
self.boat = (KINDS[kind].build(laden=wanted, room=room)
             if KINDS[kind].cargo else KINDS[kind].build())
```

`build` is in `Kind.__slots__` (traffic.py:766) holding `vessel.spits`,
`vessel.barge` and so on. Varied to find the boundary: positional arguments
compile, hoisting the receiver to a local does NOT help, removing the
conditional expression does NOT help. Which fits this ticket exactly — hoisting
to a local would have helped if the field were the problem, and it does not,
because `KINDS[kind]` is still a subscript at the point that matters.

The `:277` arity error in front of it is a SUBJECT-ONLY artefact and not a bug:
traffic.py does not import world, so exactly one class declares `nearest` and
the compiler takes its statically-resolved arm. Compile traffic beside world and
`:277` is gone and `:375` is the wall.

### Two messages, one construct

Worth knowing before anyone counts these as two walls:

| context | message |
| --- | --- |
| the corpus, traffic.py:375 | `expected ')' before '='` |
| a two-module reduction of the same shape | `undefined variable (laden)` |

Same call, same door, discriminated by what else is linked — the message-level
version of the cascade artefact.

### Positive control for whoever fixes it

The plain-name and function-call receivers must KEEP working, out of declaration
order, and a dict of two functions with different parameter names must still
bind per-callee (`alpha(laden, room)` and `beta(width, depth)` in one dict).
`test/test_nilpy_double_star_at_a_callable_value_call.npy` pins the `**`
spelling of the same family and is the file to extend.
