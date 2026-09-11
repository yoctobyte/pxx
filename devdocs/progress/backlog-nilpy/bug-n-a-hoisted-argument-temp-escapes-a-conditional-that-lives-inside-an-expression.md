---
track: N
prio: 55
type: bug
owner: unassigned
blocked-by: []
summary: "`g(b=side(2), a=1) if False else 'x'` prints `evaluated 2` and CPython prints nothing — the hoisted TPyList that carries `*iterable`, `**mapping` and `name=value` to a dynamically-dispatched call lands at the enclosing STATEMENT, which is above a ternary and above a comprehension filter. Correct in an `if` statement, a dead loop and an `or` short-circuit; wrong in the two shapes where the conditional is inside an expression. A side effect that should not happen, no diagnostic."
---

# A hoisted argument temp escapes a conditional that lives inside an expression

A call through a callable VALUE cannot resolve `*`, `**` or a keyword name at
compile time, so the argument list is built at run time in a hoisted container
temp: `PyNewContainerTemp` allocates a `TPyList`/`TPyDict` and the appends are
emitted as STATEMENTS ahead of the expression that uses it.

The hoist lands at the enclosing **statement**. That is above a conditional
EXPRESSION and above a comprehension's filter, so the appends run whether or not
the arm that contains the call is taken.

```python
def side(v):
    print('evaluated', v); return v
def f(a, b): return ('f', a, b)
g = f

print(g(b=side(2), a=1) if False else 'other-branch')
print([g(b=side(4), a=1) for i in [1] if False])
```

CPython prints `other-branch` and `[]`. pxx prints `evaluated 2` and
`evaluated 4` first.

## The boundary, measured 2026-09-11 at compiler 4091331fdf95

| shape | result |
| --- | --- |
| conditional expression, `a(...) if c else b` | **over-evaluates** |
| comprehension with a filter, `[a(...) for i in xs if False]` | **over-evaluates** |
| `True or g(b=side(2), a=1)` | correct |
| a `for` body over an empty iterable | correct |
| an `if` STATEMENT arm not taken | correct |

The three correct rows are the useful half: they say the hoist is statement-local
and working, so this is not "hoisting is wrong", it is "two alternatives share one
statement".

## It is the CHANNEL, not keywords — and the control says so

`f(b=side(2), a=1)` with a PLAIN-NAME callee, in the same ternary, is correct.
That path binds the name at compile time through `PyKwArgIndex`/`PyBindKwArgs`
into an ordinary argument chain and hoists nothing. So the discriminator is
whether the callee was statically known, exactly as it is for the parse-time
failures this channel was built to fix.

`*iterable` through a callable value has it too and PREDATES the keyword work
(`g(*xs, side(2)) if False else ...` prints `evaluated 2`), which is what makes
this a property of the hoisting channel rather than of any one door.

## NOT BLOCKED ON ANYTHING, AND NOT WAITING FOR A DOOR TO LAND

Said explicitly because the two keyword doors were found and fixed the same
evening and it would be easy to park this behind them. It is about
`PyNewContainerTemp`'s hoist PLACEMENT, not about any one call shape:
`g(*xs, side(2)) if False else ...` over-evaluates and the star channel predates
both keyword doors. Whoever takes it should not wait for anything of mine.

## Population

Every dynamically-dispatched call carrying `*`, `**` or `name=value`:
`PyMakeDynCall` (a callable in a variable, a dict value, a list element) and
`PyMakeVariantFieldCall` (a callable field on a variant receiver). Both reach
`PyNewContainerTemp`.

## Why it is not urgent, said honestly

The wrong OUTPUT needs a keyword or star VALUE with a side effect, in a ternary
or a filtered comprehension. lekkerzeilen/traffic.py:375 is exactly the ternary
shape and is unaffected in value, because its keyword values are plain locals.
Ranked 55 rather than higher for that reason, not because the mechanism is
narrow — the mechanism is every such call.

## What a fix has to do

Emit the container construction into the arm rather than ahead of the statement,
which means the ternary and the comprehension filter need a place to put
statements — or the channel needs a form that builds the list as an EXPRESSION.
The second is the one that also removes the hoist's interaction with evaluation
ORDER, which nothing currently asserts.

## The assertion class this needs

An `expect_same` row on the RESULT cannot see it: both arms produce the correct
value and the defect is an extra side effect. The fixture must print from inside
the argument expression and compare the LOG, the same instrument the assignment
-order bug needed.
