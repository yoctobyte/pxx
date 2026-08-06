---
track: N
prio: 30
type: feature
summary: "Five ordinary Python forms NilPy diagnoses cleanly but does not accept: str.format() with 3+ placeholders, enumerate(str), type(x) other than .__name__, a non-name lambda default, print(sep=)"
---

# Small NilPy syntax gaps found by the 2026-08-06 differential sweep

(Extended later the same day as the sweep widened from unit-shaped probes to
real programs; the last four rows came from a JSON writer, a hash table and a
matrix builder rather than from targeted probing.)

- **Type:** feature (subset boundary) — **Track N**
- **Found:** 2026-08-06, bughunting with `tools/pydiff.py`.

All of these **fail loudly**, and most with a clear, accurate diagnostic — none is a silent
wrong value, and each names its workaround. They are grouped in one ticket because each is small and they were found in one
sweep; split if any turns out to be substantial. The last three rows have the
weakest diagnostics — *"undefined variable (c)"* and *"expected expression"* do
not tell the author that the FORM is unsupported, which is worth fixing even
before the forms themselves are.

| form | today's diagnostic |
| --- | --- |
| `"{} {} {}".format(a, b, c)` | *".format() takes one or two arguments here; three or more placeholders are not implemented yet — use an f-string"* |
| `enumerate("ab")` | *"enumerate() over a str is not supported yet — enumerate(list(s)) works"* |
| `type(1) == int` | *"type(x) is only supported as type(x).__name__"* |
| `lambda x, y=1: x + y` | *"a lambda default capture must be a plain name (key=key)"* |
| `print("a", "b", sep="-")` | *"print sep= is not supported yet"* |
| `d = dict(x=1, y=2)` | *"dict has no parameter named 'x'"* |
| `f.update(b=2)` | *"TPyDict.update has no parameter named 'b'"* |
| `c[::2] = [7, 8]` (extended-slice assign) | *"assigning to an extended slice (with a step) is not implemented; only x[lo:hi] = src is"* |
| `self.__class__.__name__` | `AttributeError: 'Base' object has no attribute '__class__'` (runtime) — note `type(self).__name__` works |
| `(c, d), e = (3, 4), 5` (nested unpacking) | *"undefined variable (c)"* |
| `t = 1, 2, 3` (bare tuple, no parens) | *"expected expression"* — note `t = (1, 2, 3)` and `p, q = two()` both work |
| `[(i, j) for i in range(2) for j in range(2)]` (two-`for` comprehension) | *"undefined variable (j)"* |

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
