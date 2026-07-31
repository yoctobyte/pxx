---
track: N
prio: 60
type: bug
---

# A comprehension's loop variable leaks and OVERWRITES the enclosing binding — and can segfault

```python
x = 5
ys = [x for x in [1, 2, 3]]
print(x)          # CPython: 5     pxx: 3
```

Python 3 gives a comprehension its OWN scope: the loop name is local to it and
the enclosing binding is untouched. (This is one of the deliberate Python 2 → 3
changes.) pxx runs the loop in the enclosing scope, so an outer variable that
happens to share the name is silently destroyed.

Worse, rebinding across types crashes:

```python
xs = [1, 2, 3]
r = [xs for xs in [9]]
print(xs)         # CPython: [1, 2, 3]     pxx: SIGSEGV
```

`xs` is a list in the outer scope and an int inside the comprehension; the
comprehension writes the int over the managed binding and the next use of it
dereferences a number as an object.

## Measured — every comprehension form, and only comprehensions

| case | CPython | pxx |
| --- | --- | --- |
| `x = 5; [x for x in [1,2,3]]; x` | `5` | `3` |
| `k = "outer"; {k: 1 for k in ["a","b"]}; k` | `outer` | `b` |
| `v = 99; {v for v in [1,2]}; v` | `99` | `2` |
| `a = "outer"; [[a for a in [1,2]] for b in [1]]; a` | `outer` | `2` |
| the same inside a function body | `5` | `2` |
| loop name NOT bound outside, read after | `NameError` | `3` (leaks a new binding) |
| `xs = [1,2,3]; [xs for xs in [9]]; xs` | `[1,2,3]` | **SIGSEGV** |
| a plain `for` loop leaking its variable | leaks | leaks — correct, Python does this |

The plain `for` statement is right: Python DOES leak there, and pxx matches. It
is specifically the comprehension forms — list, dict, set, and the inner clause
of a nested one — that must not.

## Shape of a fix

The comprehension lowering already synthesises a hidden accumulator
(`PyCompTarget` and the `PyHiddenName` helper are right there). The loop
variable wants the same treatment: bind it to a generated name for the duration
of the comprehension and rewrite references to it inside the clause, rather than
resolving it against the enclosing scope. That also removes the crash, since the
outer managed binding is then never written.

Watch the nested case — `[[a for a in ...] for b in ...]` — where each clause
needs its own hidden name, and the case where the comprehension legitimately
READS an enclosing variable of a different name (that must keep resolving
outward).

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` covering the table
above with CPython's own output as the expectation — including the segfault
case, which must print `[1, 2, 3]`.

## Log
- 2026-07-31 — resolved, commit fd5bf5825.
