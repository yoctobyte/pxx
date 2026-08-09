---
track: N
prio: 35
type: feature
---

# `with A() as a, B() as b:` — only one context manager per `with`

```python
with Ctx(3) as a, Ctx(4) as b:      # error: Expected: :, but got: (Kind: 80)
    print(a.n, b.n)
```

A compile error. Single-manager `with` is fully correct — a CPython-diffed
sweep of `__enter__`/`__exit__`, the exception path and `as` binding all matched
exactly, so this comma form is the only gap in the statement.

It is pure sugar: `with A() as a, B() as b:` is defined as nesting, so the
lowering is a loop over the comma-separated managers producing nested blocks.
The `__exit__` ORDER matters and is what a test must pin — inner exits first,
and an exception in the body must still exit both, innermost first.

Common in file-handling code (`with open(a) as f, open(b) as g:`), which is why
it is filed rather than left as a curiosity.

## Gate

`make test-nilpy` + self-host byte-identical, CPython-diffed over two and three
managers, `as`-less managers mixed with bound ones, exit ORDER, and an exception
raised in the body (both managers must exit, innermost first).
