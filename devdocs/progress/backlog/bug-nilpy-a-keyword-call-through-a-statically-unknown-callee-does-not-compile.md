---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`a = mk(1); a(x=5)` fails to COMPILE — `error: undefined variable (x)` — because the keyword-argument lowering only fires when the frontend can resolve the callee to a def/lambda by name. The runtime dispatcher handles this fine (a callee reached as a PARAMETER works), so it is the parse-time gate, not the call path."
---

# A keyword call through a statically unknown callee does not compile

- **Type:** bug (NilPy frontend) — **Track N** (`compiler/pyparser.inc`).
- **Filed by:** frank2 on Track A, 2026-08-19, while probing
  [[refactor-a-one-signature-record-for-every-callable-carrier]] — that refactor
  gave the RUNTIME dispatcher the names it needed, and this is the remaining
  half: some call sites never reach the dispatcher at all.

## Measured at HEAD (9477001a8, self-host converged)

```python
def mk(k):
    g = lambda x, y=2: x * 100 + y + k
    return g
a = mk(1)
print(a(x=5))
```

    pascal26:5: error: undefined variable (x)
      near:  print  a  x >>>

CPython prints `501`. The keyword NAME is being parsed as an ordinary
expression identifier, which is what "undefined variable (x)" is reporting.

## The same call through a PARAMETER compiles and is correct

```python
def use(g):
    return g(y=5, x=6)
f = lambda x, y=2: x * 10 + y
print(use(f))                  # 65, matching CPython
```

So the lowering to `pyvar_callv_kw` and the runtime name matching both work.
The difference is only whether the frontend could name a candidate callee at
the call site: a parameter cannot be resolved statically, so that site takes the
dynamic path — while `a`, a local holding a call RESULT, apparently is looked up
and, finding no def named `a`, falls back to treating `x=5` as an expression.

## Why it matters

It is a COMPILE error, so it cannot be worked around at runtime, and it hits the
common closure-factory shape. It also inverts the usual expectation: the case
the frontend knows LESS about is the one that works.

## Suggested first look

Wherever the argument parser decides that `name =` is a keyword argument rather
than an expression. That decision should depend on the SYNTAX (an identifier
followed by `=` at argument level is always a keyword argument in Python), not
on whether a candidate callee was resolved — resolution can then supply the
better diagnostic, but should not gate the parse.
