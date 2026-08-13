---
track: N
prio: 30
type: feature
summary: "Ordinary Python forms NilPy diagnoses cleanly but does not accept. print(sep=) and str.format() with 3+ (and 0) placeholders are DONE (2026-08-08); ten rows remain: enumerate(str), type(x) other than .__name__, a non-name lambda default, dict(x=1), .update(b=2), extended-slice assign, self.__class__.__name__, nested unpacking, bare tuple, two-for comprehension"
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

## 2026-08-08 — two rows done: `print(sep=)` and `.format()` with 3+ (and 0)

Re-measured all twelve rows first; every one still failed as recorded. Two are
now fixed. The ticket stays open for the other ten.

### `print("a", "b", sep="-")`

The refusal carried its own reason — *"separators are injected DURING the
argument loop, while a keyword argument is only seen after it"* — and that was
true, so the fix was to stop reading it in the loop. `PyPrintSepAhead`
(pyparser.inc) scans this call's own token range for `sep=<string literal>`
before any argument is parsed, so the value is known when the first separator
is built. Depth-tracked over parens, brackets and braces, so a NESTED call's
own `sep=` keyword, a list/dict display, an f-string or a subscript inside the
argument list cannot be mistaken for print's own.

`sep=""` injects nothing (the arguments abut). A literal is required, like
`end=` — the separator is materialised at parse time as the constant between
two arguments, so a run-time value would need a different lowering. `print(*x)`
with `sep=` is refused: `pyprint_star` renders a whole unpacked run into one
string with the space hard-coded, and silently ignoring the sep on the starred
run only would be worse than saying so.

### `"{} {} {}".format(a, b, c)`

The one-proc-per-arity scheme (`pystr_format`, `pystr_format2` — separate names
because `FindProc` is not arity-aware) does not extend, so it ends here rather
than growing a third name. `pystr_formatn` is one FIXED-arity proc taking eight
Variants plus a real count; the frontend pads the unused slots with `pynone`.
Past eight it refuses loudly and names f-strings, which have no limit.

The substitution itself moved to ONE place — `PyFormatApply` now takes the
argument LIST rather than `(a, b, nArgs)` — so positional indices (`{0} {2}
{1}`, `{2}-{2}`) and format specs cannot drift between arities. Arity 1 and 2
go through the same code via one- and two-element lists.

Zero arguments (`"plain".format()`) is valid CPython and was refused by the same
gate; it routes through `pystr_formatn` with n=0.

Tests: `test/test_nilpy_print_sep.npy`, `test/test_nilpy_format_multiarg.npy`,
both wired into `make test-nilpy` and diffed against CPython (exact match).

### Still open

`enumerate(str)`, `type(x) == int`, non-name lambda default, `dict(x=1)`,
`.update(b=2)`, extended-slice assign, `self.__class__.__name__`, nested
unpacking, bare tuple `t = 1, 2, 3`, two-`for` comprehension.

## 2026-08-13 — re-measured all ten remaining rows: FIVE are gone, five stand

Four had been fixed elsewhere since and were still recorded as open. Measured,
not assumed — each row run against CPython:

| row | now |
| --- | --- |
| `"{} {} {}".format(a, b, c)` | **works** |
| `enumerate("ab")` | **works** |
| `dict(x=1, y=2)` | **works** (landed with the keywords-are-keys builder) |
| `[(i, j) for i in range(2) for j in range(2)]` | **works** |
| `self.__class__.__name__` | **fixed here** |
| `type(1) == int` | still refused, by name |
| `lambda x, y=1: x + y` | still refused, by name |
| `f.update(b=2)` | still refused (see its own ticket — it SEGFAULTS on two keywords, which is why it is not just a parse gap) |
| `c[::2] = [7, 8]` | still refused, by name |
| `(c, d), e = (3, 4), 5` | still `undefined variable (c)` |
| `t = 1, 2, 3` | still `expected expression` |

### `self.__class__.__name__` — fixed

It raised `AttributeError: 'B' object has no attribute '__class__'` at RUN time
while `type(self).__name__` answered — one question, two spellings, one of them
working, which is this frontend's recurring shape.

Lowered to the SAME `pytype_name_v` call `type(x).__name__` uses, deliberately:
a second lowering would be a second thing to get wrong for tuples, sets and
scalars, which is precisely what that one call exists to get right.

**Only the full chain.** A bare `x.__class__` is a class OBJECT in Python and
this frontend has no such value, so it keeps its AttributeError instead of
being given an invented answer — the same call bare `type(x)` already makes a
few lines away.

**Two parsers had to learn it**, and testing only the first would have shipped
it half-done: a bare name and `self` take parser.inc's member access, while a
call result and a subscript take pyparser's selector twin. One builder
(`PyMakeClassNameOf`), both call sites.

Left unsupported: a LITERAL receiver, `(1).__class__.__name__`, which does not
parse. `type(1).__name__` is the spelling for that and works.

Test `test/test_nilpy_class_name_chain.{npy,expected}`, wired into `test-nilpy`.
