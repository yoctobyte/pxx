---
track: N
prio: 50
type: bug
---

# `xs.sort(key=..., reverse=...)` fails with a bare "unexpected token"

- **Type:** bug (missing feature + poor diagnostic) — **Track N**
- **Found:** 2026-08-02, by a differential sweep against the CPython oracle.

## Measured

```python
xs = [3, 1, 2]
xs.sort(reverse=True)
```
```
error: unexpected token
  near:   xs  sort  >>> reverse
```

Same for `xs.sort(key=len)`. Meanwhile `sorted()` supports both:

| form | result |
| --- | --- |
| `sorted(xs, reverse=True)` | ok |
| `sorted(xs, key=len)` | ok |
| `sorted(xs, key=len, reverse=True)` | ok |
| `xs.sort()` | ok |
| **`xs.sort(reverse=True)`** | **parse error** |
| **`xs.sort(key=len)`** | **parse error** |

## Two things wrong

**1. The feature is missing.** `TPyList.sort`'s own comment says `key=`/
`reverse=` are not implemented because they need `PyCallKey1`'s callable
dispatch, which lives in `pyeval.pas` — and `pyeval uses pylib`, not the
reverse, so pylib cannot call it. That is a real constraint and honestly
documented.

But `sorted()` — which DOES live in `pyeval.pas` — already implements both,
including the insertion sort that moves a computed-key list in lockstep. So the
in-place method could delegate: sort into a new list with the existing code,
then copy back. `TPyList.reverse` (added 2026-08-02) is the same in-place
shape.

**2. The refusal is not loud, it is confusing.** The comment says these are
"refused loudly rather than guessed at", but what the user sees is a generic
`unexpected token` pointing at the keyword name — indistinguishable from a typo
in their own code. Compare the str-method table, which says exactly what is
wrong (`str method .find() takes one or two arguments`). Even without the
feature, this should name it.

## Gate

A `.npy` diffed against CPython covering `sort()` with `reverse`, with `key`,
with both, on an empty list and a single-element list, and confirming the sort
is IN PLACE (the original name observes the new order) with the return value
being `None` as Python's is.

## 2026-08-02 — `min()` / `max()` reject `key=` too

Same sweep, same family, different route — this one is a named diagnostic rather
than a parse error:

```python
words = ["bb", "a", "ccc"]
print(min(words, key=len))    # pascal26: error: Nil Python: min has no parameter named 'key'
print(max(words, key=len))    # same
```

`sorted(words, key=len)` and `sorted(..., reverse=True)` fail here as well, so
the `key=` callable is missing across the whole comparison family — `sort`,
`sorted`, `min`, `max` — not just the list method this ticket was filed for.
They should be gated together: whatever mechanism passes a callable into the
comparison is one piece of machinery serving all four.

`sorted(xs)`, `sorted(xs, reverse=...)` as the ONLY kwarg, `min(xs)` and
`max(xs)` without a key all work today.
