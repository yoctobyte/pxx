---
track: N
prio: 35
type: feature
---

# `yield` only works inside a `for` — a while-loop generator does not compile

```python
def gen(n: int):
    i = 0
    while i < n:
        yield i          # error: undefined variable (yield)
        i = i + 1
```

The same generator written with `for i in range(n): yield i` also fails today,
so the working surface is narrower than the "for-in/yield" support suggests —
worth establishing exactly which shape does work before starting.

`yield` reported as an "undefined variable" says it is not being recognised as
a statement at all in this position, so the parse arm is keyed to a context
rather than the keyword.

Found by sweeping generator/ternary/unpacking constructs against CPython.

## Recon 2026-07-31 — bigger than the title suggests, not attempted

Measured, not assumed: `grep -n "'yield'" compiler/pyparser.inc` returns ZERO
matches. `yield` is not recognised ANYWHERE in the NilPy frontend today — not
"works inside `for`, fails inside `while`" as the title implies, but
unimplemented full stop. Confirmed directly: `for i in range(n): yield i`
(the shape the title says already works) ALSO fails with the same "undefined
variable (yield)" — matching the ticket body's own footnote, not the title.

`CurProcIsGenerator`/`CurGenSelfSym`/`GenTryDepth` and the "stackful
coroutine body" machinery mentioned around `PyParseDef` (pyparser.inc) exist
for a Pascal-only `; generator;` directive — there is no NilPy-side wiring
to it, automatic or otherwise. So this isn't a parse-context bug to
relocate; it's full Python generator support to build: recognising a
`yield`-containing `def` as a generator automatically, giving it suspend/
resume semantics (there IS a coroutine backend to potentially reuse, just
not connected), and the iteration protocol (`for x in gen()`, `list(gen())`)
on top. Sized like the other bigger, dedicated-pass features in this
backlog (`feature-nilpy-lambda-compiled-closure`, closure-ABI items), not
like a quick bug fix. Not attempted this session — retitling the fork
correctly (unimplemented feature, not a narrow context bug) is the useful
output of this recon.

## Gate

`make test-nilpy` + self-host byte-identical, plus generators driven by
`while`, by `for ... in range`, and by `for ... in <list>`, each consumed by a
`for` loop and by `list()`.
