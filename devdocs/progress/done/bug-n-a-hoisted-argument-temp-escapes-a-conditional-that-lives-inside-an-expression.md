---
track: N
prio: 80
type: bug
owner: unassigned
blocked-by: []
summary: "`g(b=side(2), a=1) if False else 'x'` prints `evaluated 2` and CPython prints nothing — the hoisted TPyList that carries `*iterable`, `**mapping` and `name=value` to a dynamically-dispatched call lands at the enclosing STATEMENT, which is above a ternary and above a comprehension filter. Correct in an `if` statement, a dead loop and an `or` short-circuit; wrong in the two shapes where the conditional is inside an expression. A side effect that should not happen, no diagnostic."
status: done
---

# A hoisted argument temp escapes a conditional that lives inside an expression

**RAISED TO 80 ON 2026-09-15: the sibling ticket
`bug-n-a-hoisted-argument-escapes-a-ternary-s-untaken-branch` now carries a
THIRD instance of this same root cause that CRASHES on correct Python**
(`staged.pending() if staged is not None else {}` raises AttributeError, rc=217,
where CPython prints a result), found on the lekkerzeilen demo. Same mechanism,
same fix, one of them fatal. Fix once and close both; use the crashing row as
the acceptance test, since it is the only member of the family that fails
loudly.

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

## Log
- 2026-09-15 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 87d0fae10.


## Resolution

Fixed with its sibling `bug-n-a-hoisted-argument-escapes-a-ternary-s-untaken-branch`
-- one root cause, three symptoms, one change. That ticket carries the full
write-up; this is the short form.

BOTH shapes this ticket names are now correct:

| shape | before | after |
|---|---|---|
| `g(b=side(2), a=1) if False else 'x'` | prints `evaluated 2` | **prints nothing** |
| `[g(b=side(4), a=1) for i in [1] if False]` | prints `evaluated 4` | **prints nothing** |

They were two DIFFERENT hoist sites, which is why one change had to touch two
places:

* the conditional expression -- `PyParseBoolExpr` now snapshots the hoist queue
  before the then-arm and folds each arm's setup INTO that arm with
  `PyFoldHoistSince`;
* the comprehension filter -- the element's hoisted setup is taken off the queue
  before the filter is parsed and placed inside the filter's TAKEN arm, instead
  of being spliced into the loop body ahead of the `AN_IF`.

In both, the CONDITION's own hoists deliberately stay where they were: a
condition always runs, so statement level is correct for them.

The three CORRECT rows this ticket recorded -- `or` short-circuit, a dead `for`
body, an untaken `if` arm -- are unchanged and were the evidence that the hoist
was statement-local and working, which is what made "attach each arm's setup to
THAT arm" the right shape rather than "stop hoisting".

Guarded by `test/test_nilpy_a_conditional_expression_does_not_evaluate_the_untaken_arm.npy`
(13 rows, wired into the tier), which holds all three symptoms in ONE file on
purpose: a reader who breaks the hoist fold should see them go red together. Its
rows were verified to FAIL before the fix rather than assumed to, and the
comprehension half's failure shape is this ticket's own argument in miniature --
every VALUE row passed and only the side-effect COUNTS were wrong (`got 2 want
0`, `got 4 want 2`, `got 6 want 2`), so no value comparison could ever have
caught it.

Now unblocked and deliberately NOT done here: `PyMakeDynMethCall`'s two paths
split only because of this bug and its own comment says to merge them when it is
fixed. That is a separate change; doing it in the same commit would make a
regression in either one unattributable.
