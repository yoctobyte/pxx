---
track: N
prio: 55
type: bug
summary: "A lambda whose body is an EXPRESSION AROUND a call (`lambda: f() or 4`, `lambda: f() + 1`) is not lifted — it falls to the pyeval interpreter, which cannot call a compiled def, so it dies at RUN time with `pyeval: unknown call: f()`. A bare `lambda: f()` works."
status: done
owner: claude-AN-night
---

# lambda body that is an expression *around* a call cannot call a def

- **Type:** bug (NilPy — runtime failure, not a compile error) — **Track N**
- **Found:** 2026-08-02, incidentally, while gating
  [[bug-nilpy-and-or-evaluates-the-left-operand-twice]]. Pre-existing: reproduced
  identically on the pinned stable binary and on HEAD (same byte size, same
  message), so it is **not** a regression from that fix.

## Measured

```python
def top():
    return 5

f = lambda: top()          # works      -> 5
h = lambda: top() + 1      # RUNTIME FAILURE
print(h())
```

```
pyeval: unknown call: top()
exit 1
```

`lambda x: x + 1` (no call at all) works. The failure needs *a call inside a
larger expression*.

## Root cause — read out of the source

`PyParseLambdaStub` (`compiler/pyparser.inc`) has two paths:

- **lifted** — the lambda is compiled as a real proc, so calls go through the
  ordinary call path. This is the good path.
- **pyeval closure** — the body is kept as SOURCE TEXT and interpreted at run
  time by `compiler/builtin/pyeval.pas`. That interpreter has no access to the
  program's compiled procs, so any call in the body reaches
  `EvalError('unknown call: ' + name + '()')` (`pyeval.pas:2773`).

Which path is taken is gated on `PyLambdaBodyIsDiscardableCall(bStart, bEnd)`
(`pyparser.inc:4669`), which accepts the body only when it is *exactly* one call:
it requires the first token to be an identifier, the LAST token to be `)`, and at
depth 0 nothing but `tkIdent` / `tkDot` (the callee chain `a.b.c(`).

So `top() + 1` is rejected at the `+` (a depth-0 token that is neither ident nor
dot) and drops to the interpreter — which is precisely the case that cannot work
there. The predicate's name is accurate about what it tests; the problem is that
what it tests is much narrower than what the lifted path can actually handle.

## Shape of a fix

The lifted path compiles an arbitrary expression body — nothing in it is
specific to a bare call; the predicate is the only thing holding it back. So the
narrow, measurable step is to **widen the predicate** rather than touch the
lifter: accept a body that *contains* a call anywhere (any `tkIdent` immediately
followed by `tkLParen`), not only one that IS a call.

Care needed on what the lift genuinely cannot take, which is why the predicate
was written conservatively — the capture scan below it walks body tokens and
only handles names resolvable via `PyProgSym` / `PyQualifyNested`. Widening the
predicate exposes that scan to shapes it has not seen (subscripts, nested
lambdas, comprehensions). Suggested order:

1. widen to "contains a call, and every depth-0 token is an operator/ident/dot/
   literal" — i.e. a flat expression;
2. gate each further shape (subscript, nested lambda, comprehension) on its own
   measurement rather than in one jump.

Anything still rejected keeps the pyeval fallback, which is what makes the
widening safe to do incrementally.

## Better long-term

The pyeval fallback failing on *any* call is the real sharp edge: it is a run
time error for something the compiler could have diagnosed. Either the fallback
should refuse at COMPILE time when the body contains a call (a clear message
naming the lambda), or it should go away entirely once the lifter covers enough.
The current behaviour — compile clean, die later with an interpreter-flavoured
message — is the worst of the three.

## Gate

`.npy` diffed against CPython covering `lambda: f() + 1`, `lambda: f() or 4`,
`lambda x: f(x) * 2`, a lambda calling a *method*, and a lambda calling a nested
def that has captures (the transitive-capture case `PyParseLambdaStub` already
documents). Plus the existing lambda tests staying green.


## Resolved 2026-08-03 — the predicate was the whole of it

Widening `PyLambdaBodyIsDiscardableCall` was the fix, exactly as the ticket
suspected, and the lifted path needed no change at all. Renamed
`PyLambdaBodyIsLiftable`, since "is a discardable call" stopped describing what
it tests.

It now accepts any FLAT expression that CONTAINS a call, instead of a body that
IS one call. The old rule demanded the first token be an identifier, the last a
`)`, and nothing but ident/dot at depth 0.

Two conditions survive, and they are what keeps this safe:

- the body must contain a call. A body without one already works through the
  pyeval closure, and lifting it would be a behaviour change for no gain.
- every depth-0 token must be one `PyLambdaTokText` can render. The lifted body
  is reconstructed as SOURCE from the token span, and an unrenderable token is a
  hard `Error`, not a fallback — so the allowlist is written against that
  function's own case list rather than against what "looks like an expression".
  A float literal has no case there, and is therefore still rejected (and still
  gets the interpreter), which is the pre-existing behaviour.

The ticket's step 2 (subscripts, nested lambdas, comprehensions one at a time)
is deliberately not taken: those are shapes the capture scan below the predicate
has not been measured against.

### One behaviour change worth stating

A lambda over a **capturing sibling nested def** used to fall to the interpreter
in its `add(10) + 1` spelling and fail at run time; it now fails at COMPILE with
`undefined variable (add)` — which is the same error the bare `add(10)` spelling
already gave on pinned. Consistency rather than a new fault, but a program that
merely BUILT before, without ever invoking such a lambda, now does not. Filed as
[[bug-nilpy-lambda-over-a-capturing-nested-def-does-not-compile]] (pre-existing,
reproduced on pinned, independent of the body shape).

### Verified

`test/test_nilpy_lambda_expression_body.npy` (+ `.expected`, wired into
`make test-nilpy`), byte-identical to CPython across 9 lines: `f() + 1`,
`f() or 4` with the side effect counted, `f(x) * 2`, `f(x) + f(x)`, a comparison
result, a ternary over two calls, a METHOD call on a captured object, the bare
`f()` form as a control, and a body with no call at all as the other control.
Pinned prints the first line and then dies with `pyeval: unknown call: top()`.

`gate.sh quick` GREEN, self-host fixedpoint byte-identical, FPC seed clean.

## Log
- 2026-08-03 — resolved.
