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

## Gate

`make test-nilpy` + self-host byte-identical, plus generators driven by
`while`, by `for ... in range`, and by `for ... in <list>`, each consumed by a
`for` loop and by `list()`.
