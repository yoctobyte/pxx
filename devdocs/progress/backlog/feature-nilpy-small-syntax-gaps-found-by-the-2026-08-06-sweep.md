---
track: N
prio: 30
type: feature
summary: "Five ordinary Python forms NilPy diagnoses cleanly but does not accept: str.format() with 3+ placeholders, enumerate(str), type(x) other than .__name__, a non-name lambda default, print(sep=)"
---

# Small NilPy syntax gaps found by the 2026-08-06 differential sweep

- **Type:** feature (subset boundary) — **Track N**
- **Found:** 2026-08-06, bughunting with `tools/pydiff.py`.

All five **fail loudly with a clear, accurate diagnostic** — none is a silent
wrong value, and each names its workaround. They are grouped in one ticket
because each is small and they were found in one pass; split if any turns out to
be substantial.

| form | today's diagnostic |
| --- | --- |
| `"{} {} {}".format(a, b, c)` | *".format() takes one or two arguments here; three or more placeholders are not implemented yet — use an f-string"* |
| `enumerate("ab")` | *"enumerate() over a str is not supported yet — enumerate(list(s)) works"* |
| `type(1) == int` | *"type(x) is only supported as type(x).__name__"* |
| `lambda x, y=1: x + y` | *"a lambda default capture must be a plain name (key=key)"* |
| `print("a", "b", sep="-")` | *"print sep= is not supported yet"* |

Everything else the sweep covered agrees with CPython: int/float arithmetic and
division semantics, string methods and slicing, list/dict/set operations and
comprehensions, classes with inheritance and `super()`, `__str__`/`__eq__`/
`__lt__`/`__add__`/`__len__` on a statically-known instance, closures, default
args, exceptions (`try/except/else/finally`, custom classes, `IndexError`/
`KeyError`/`ValueError`), aliasing and mutable-default semantics, f-strings with
width/precision/alignment specs, `%`-formatting, `for/else`, `while/else`,
chained comparisons, and `sorted(key=…, reverse=…)`.

The real bugs that same sweep found are filed separately:
[[bug-nilpy-augmented-assignment-truncates-to-32-bits]],
[[bug-nilpy-floordiv-mod-compare-and-float-narrow-a-variant-held-bignum]],
[[bug-nilpy-int-of-a-long-decimal-string-narrows]],
[[bug-nilpy-for-rejects-an-inline-suite]].

`sorted()` over instances with `__lt__` also raises, but that is already
[[bug-nilpy-dunders-not-dispatched-through-containers]] (blocked on
[[decide-nilpy-runtime-dunder-dispatch-strategy]]) — this sweep re-confirmed it,
it is not a new find.

## Gate

Per-fix loop, per item. A `.npy` test per form diffed against CPython.
