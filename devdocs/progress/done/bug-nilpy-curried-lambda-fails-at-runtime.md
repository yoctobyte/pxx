---
prio: 40
track: N
type: bug
blocked-by: []
status: done
---

# A lambda whose body is another lambda dies at RUN time

- **Type:** bug (NilPy) — **Track N**
- **Found:** 2026-08-09 by a differential sweep of closures and nested defs.
- **Owner:** agent-AN

```python
add = lambda a: lambda b: a + b
print(add(3)(4))        # CPython 7
                        # pxx    pyeval: name not defined: lambda   (exit 1)
```

## Narrowed

| shape | result |
| --- | --- |
| `lambda a: lambda b: a + b` | **runtime failure** |
| `def outer(a): return lambda b: a + b` | works |
| `lambda a: a + 1` | works |

So it is exactly a lambda whose BODY is a lambda. The message comes from
`pyeval` — the inner lambda's source text reaches the interpreter, which has no
`lambda` keyword of its own.

## Not a surprise, but not tracked either

[[bug-nilpy-lambda-body-expression-around-a-call-cannot-call-a-def]] (done)
records that its step 2 — "subscripts, nested lambdas, comprehensions one at a
time" — was **deliberately not taken**, because those shapes had not been
measured against the capture scan under the lift predicate. So this is a known
unhandled shape; what it did not have is a ticket saying what it costs, which
is a runtime failure rather than a slow path.

It sits under [[feature-nilpy-lambda-compiled-closure]] (lambdas are interpreted
rather than compiled) but is worth its own row because the failure is not
performance: the program dies.

## Two routes

1. **Extend the lift predicate to a lambda-bodied lambda.** Two of the three
   questions are already answered, by reading rather than guessing:

   - **`PyLambdaTokText` CAN render it.** `lambda` lexes as a `tkIdent` in
     NilPy (the parser tests it with `CaseEqual(GetTokenStr(j+1), 'lambda')`),
     and `tkIdent` renders as its own text. So the unrenderable-token hazard
     that gates this predicate is not what stops the nested case.
   - **The predicate's "body must contain a CALL" requirement is what stops
     it.** `lambda a: lambda b: a + b` has no call anywhere in the outer body,
     so it is never lifted and falls to the interpreter — which is where the
     error comes from. That requirement exists because "a body without a call
     already works through the pyeval closure, and lifting it would be a
     behaviour change for no gain" — an assumption that is simply false for
     this shape, since pyeval cannot run it at all.
   - **Still open:** whether the capture scan sees the INNER lambda's free
     variables (here `a`, the outer's parameter). That is the part the done
     ticket said had not been measured.
2. **Teach `pyeval` the `lambda` keyword**, so the interpreted path stops being
   a dead end. Wider, and it helps every other shape that falls back.

Route 1 is narrower; route 2 removes a whole class of "falls back and then
fails". Whichever: the currying idiom is common in argument-adapter code
(`key=lambda a: lambda b: ...` shows up in callback plumbing).

## Gate
`.npy` diffed against CPython: the curried form invoked in one go
(`add(3)(4)`) and in two steps (`f = add(3); f(4)`), the inner lambda capturing
the outer's parameter, a three-level curry, and the two shapes that already work
as controls.

## FIXED 2026-08-09 — route 1, and the open question is answered

### Two clauses rejected it, not one

The ticket identified the "body must contain a CALL" requirement. Measured,
`PyLambdaBodyIsLiftable` rejected `lambda a: lambda b: a + b` **twice**: there is
no call anywhere in the outer body, *and* the inner `:` is not in the
flat-expression token set the predicate walks — so it would have exited on the
colon before the `sawCall` test was even consulted. Both had to go.

### The relaxation is narrow on purpose

`nestedLambda` = the body's FIRST token is `lambda`. Only then are `tkColon` and
`tkComma` accepted at depth 0, and only then does `sawCall` stop being required.
Every other call-less body keeps its existing pyeval route, so this cannot become
a broad behaviour change — which matters, because the requirement's stated
justification is exactly that lifting a call-less body would be one.

That justification is what does not hold here, and the ticket had the reason
right: *"a body without a call already works through the pyeval closure"* is
false for this shape. pyeval has no `lambda` keyword, so the interpreter cannot
run the body at all and the program DIES. "Not liftable" normally means a slower
route; here it meant no route.

### The open question, answered by measurement

> **Still open:** whether the capture scan sees the INNER lambda's free
> variables (here `a`, the outer's parameter).

**It does.** Not asserted from reading the scan — asserted from behaviour that
could not work otherwise:

- `held = add(10)` then `held(5)`, `held(1)` → `15`, `11`. The outer parameter
  survives being partially applied, STORED, and called twice.
- `three = lambda a: lambda b: lambda c: a + b + c`; `three(1)(2)(3)` → `6`.
  Two levels of capture, so the scan is not merely handling one.
- A curried lambda passed as an ARGUMENT and applied inside a def → correct.
- A string-returning one (`str(a) + "," + str(b)`) → correct, so it is not
  integer-only.

All diffed against CPython.

### Route 2 is still worth having

Teaching pyeval the `lambda` keyword would remove the whole class of "falls back
to the interpreter and then fails" rather than this one shape. Route 1 was taken
because it is narrow and the failure is a hard crash today; route 2 remains open
under [[feature-nilpy-lambda-compiled-closure]].

### Gate

Extended `test_nilpy_lambda_expression_body.npy` — the test of the ticket that
DEFERRED this as "step 2", so the two now sit together and the same predicate has
one test. Covers `add(3)(4)`, the two-step form, three-level currying, a
string-returning curry, a curried lambda passed as an argument, and the two
shapes that already worked as controls. Matches CPython byte for byte; self-host
fixedpoint byte-identical.

## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
