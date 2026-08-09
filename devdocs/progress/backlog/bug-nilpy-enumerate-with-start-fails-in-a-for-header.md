---
track: N
prio: 45
type: bug
---

# `for i, v in enumerate(xs, 1):` — the start offset works everywhere EXCEPT a for header

```python
ys = ["a", "b"]

print(list(enumerate(ys, 1)))    # [(1, 'a'), (2, 'b')]   — correct

for i, v in enumerate(ys, 1):    # error: Expected: ), but got: (Kind: 80)
    print(i, v)
```

A compile error, so nothing computes a wrong answer.

`feature-nilpy-bin-oct-and-enumerate-start-offset` is in `done/` and its fix is
real — the two-argument form is implemented and correct in EXPRESSION position.
The `for` header is a second parse path that never learned it: one-argument
`enumerate(ys)` works there, two-argument does not.

Confirmed pre-existing (`stable_linux_amd64/default/pinned` fails identically),
so this is the original fix's blind spot rather than a regression.

## The shape, not just the instance

This is the two-homes pattern that keeps recurring in this frontend: a `for`
header parses its iterable separately from an ordinary expression, so anything
taught to one is invisible to the other. Worth checking, while fixing, which
other iterable-producing builtins the for-header path accepts with their full
argument sets — `zip`, `reversed`, `sorted(key=…)`, `range` with a step — rather
than fixing `enumerate` alone and leaving the next one to be reported.

## Gate

`make test-nilpy` + self-host byte-identical, CPython-diffed over `enumerate`
with and without a start, in a `for` header and in expression position, with
tuple-unpacking and single-name targets, plus the neighbouring builtins in a
`for` header with their optional arguments.
