---
track: N
prio: 55
type: bug
---

# `return` inside a `with` does not run `__exit__`

```python
class C:
    def __init__(self, n):
        self.n = n
    def __enter__(self):
        return self
    def __exit__(self, a, b, c):
        print("exit", self.n)
        return False

def one():
    with C(1) as a:
        return a.n

print("ret", one())
```

```
CPython:  exit 1 / ret 1
pxx:      ret 1
```

`__exit__` never runs. **Silent** — the value returned is correct, so nothing
looks wrong; what is lost is the release. That is a lock never released, a
transaction never rolled back, a file never closed, all with no diagnostic, on
the single most common early-exit path there is.

Confirmed pre-existing (`stable_linux_amd64/default/pinned` behaves the same)
and NOT specific to multiple managers — a single-manager `with` does it too.

## The source says otherwise, which is the useful part

`PyParseWithTail`'s own comment reads:

> try/finally so `__exit__` runs on the exception path and on break/return too.

The exception path is correct — measured, an exception inside the body does run
`__exit__`, including for several managers in the right order. So the
`AN_TRY_FINALLY` lowering is right and `return` is the arm that escapes it: the
return presumably unwinds past the finally rather than through it. `break` and
`continue` out of a loop inside a `with` should be measured at the same time —
the comment claims them together and only one of the three was verified.

## Gate

`make test-nilpy` + self-host byte-identical, CPython-diffed over `return` from
inside a `with` (single and multiple managers), `break` and `continue` out of a
loop inside one, a bare fall-off-the-end, an exception (the case that already
works, as a control), and a `return` inside a `try` inside a `with`.
