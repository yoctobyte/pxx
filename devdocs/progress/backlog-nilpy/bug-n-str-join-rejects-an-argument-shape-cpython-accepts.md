---
slug: bug-n-str-join-rejects-an-argument-shape-cpython-accepts
track: N
prio: 40
type: bug
status: backlog
owner: ""
created: 2026-09-08
found-by: frankuser
tags: [nilpy, strings, overloads, lekkerzeilen]
blocked-by: []
summary: "`no overload of join matches these arguments` at lekkerzeilen/text.py:144. Measured 2026-09-08 against compiler/pascal26 a7b03135f504. NOT YET REDUCED -- the failing argument shape has not been isolated, and the ticket says so rather than guessing, because `join` takes any iterable of str in CPython and the interesting question is which iterable shape nilpy's overload set misses (generator expression, comprehension, or a list of a non-str element type)."
---

# What is known

```
$ ./compiler/pascal26 lekkerzeilen/text.py out
pascal26:144: error: no overload of join matches these arguments
```

lekkerzeilen's runtime package uses 21 generator expressions and 20 list
comprehensions, so `sep.join(<genexp>)` is the shape to try first.

# What is NOT known, deliberately

The reduction. A first-error census stops at the first failure per module, so
this is where `text.py` stops today and nothing establishes it is the only
problem in that file. **Reduce before fixing** — the cause could be the argument
being a generator rather than a sequence, an element type, or the overload
resolution itself, and those are three different fixes.
