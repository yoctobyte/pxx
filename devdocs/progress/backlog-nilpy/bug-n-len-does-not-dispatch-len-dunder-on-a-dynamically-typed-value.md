---
track: N
prio: 60
type: bug
blocked-by: []
summary: "len(x) raises TypeError: expected an object with a length, got object whenever x's static type was not inferred, even though x's class defines __len__: an element of a list, a value out of a dict, an unannotated parameter, the return of any self-referencing or recursive function. The same value answers .attr, .method(), for-in and x[i] correctly, so len is the one protocol with no dynamic fallback."
---

# `len()` does not dispatch `__len__` on a dynamically-typed value

- **Type:** bug (Nil-Python frontend) — **Track N**.
- **Filed:** 2026-08-30 by frankB, from
  [[feature-b-sweep-mimic-shims-against-cpython]] phase 2. Surfaced as
  `len(Comment("hi"))` failing while `len(Element("e"))` worked — same class,
  same `__len__`.
- Measured at pin **v395**, CPython 3.12 as the oracle. Every row is from a run.

## Repro

```python
class C:
    def __init__(self):
        self._k = [7, 8, 9]
    def __len__(self):
        return len(self._k)

lst = [C(), C()]
print(len(lst[0]))
```

| | |
| --- | --- |
| CPython | `3` |
| pxx | `TypeError: expected an object with a length, got object` |

## The trigger is a LOST STATIC TYPE, not the class

The class is identical in every row. What changes is whether the compiler knew
the expression's type:

| `len(...)` applied to | pxx | CPython |
| --- | --- | --- |
| `z` where `z = C()` | 3 | 3 |
| `C()` inline | 3 | 3 |
| `r` where `r = mk()` and `def mk(): return C()` | 3 | 3 |
| **`lst[0]`** where `lst = [C(), C()]` | **TypeError** | 3 |
| **`d["k"]`** where `d = {"k": C()}` | **TypeError** | 3 |
| **an unannotated parameter** — `def f(x): return len(x)` | **TypeError** | 3 |
| **the return of a self-referencing def** (below) | **TypeError** | 3 |

## Any function that names ITSELF loses its return type

This is the second half of the finding and it is worth its own table, because
it includes plain recursion:

| the def's body mentions itself as... | pxx | CPython |
| --- | --- | --- |
| a constructor argument — `return C(f)` | **TypeError** | 3 |
| an attribute assigned after — `e.tag = f` | **TypeError** | 3 |
| an unused local — `x = f` | **TypeError** | 3 |
| **ordinary recursion** — `return f(n - 1)` | **TypeError** | 3 |
| a *different* function as a value — `return C(show)` | 3 | 3 |

The last row is the control: referencing some other function is fine, so this
is self-reference specifically, not "a function value appears in the body".

## `len` is the ONLY protocol without a dynamic fallback

On the very same dynamically-typed value, every other protocol dispatches
correctly:

| on `r`, the result of a recursive def returning `C` | pxx | CPython |
| --- | --- | --- |
| `r.name` | `'c'` | `'c'` |
| `r.hello()` | `'hi'` | `'hi'` |
| `for _ in r` | 3 iterations | 3 |
| `r[0]` | 7 | 7 |
| **`len(r)`** | **TypeError** | 3 |

Iteration already got exactly this treatment —
[[feature-nilpy-for-loop-getitem-protocol-fallback]], `6905fd6d0` — and `len`
did not. That is the shape of
`devdocs/dev/normalise-dont-special-case.md`: one concept, two paths, and the
second one is the one that stayed broken.

## Severity

p60. It is loud rather than silent, which is the one mercy here — this raises
instead of answering a wrong number, unlike the historic
`bug-nilpy-dunder-protocols-ignored-fall-back-to-handle-arithmetic` that the
current code's comments describe. But the reachable set is very large:
**every element of a list of objects, every value out of a dict of objects,
and every unannotated parameter** — which is most parameters in idiomatic
Python. A container class whose instances live in a list is the ordinary case,
not an edge, and `len(items[0])` is how anyone would write it.

## Suggested first look — INFERENCE, not measurement

Flagged as unverified: read the code, did not probe it. `pyparser.inc:43968`
handles `len` as a name-keyed intrinsic that TRIAL-PARSES its argument to learn
the type, then rewrites to a `__len__` call for a `tyClass` argument and
rewinds to the ordinary overload path for a pylib container. Its own comment
says *"Any OTHER class — with or without `__len__` — is handled HERE"*, which
reads as a decision keyed on the argument being a **statically known class**.
A `tyVariant`-typed argument is neither a `tyClass` nor a pylib container, so
it plausibly falls through to the Pascal overload set, whose Variant overload
is what emits this exact message.

That region is heavily commented with three past bugs (the trial parse's hoist
queue, its orphan lambda procs, and the user-shadow check), so **read those
before touching it** — the trial parse has side effects that have bitten three
times. Confirm with `PXXDBG=a.ir` on the four-line repro rather than trusting
the paragraph above.

## What it broke

`lib/rtl/mimic_xml_etree_elementtree.py`'s `Comment()` is
`def Comment(text=None): e = Element(Comment); ...; return e` — the platonic
spelling, and CPython's own, since the factory doubles as the sentinel tag. It
names itself, so `len(Comment("x"))` raises where `len(Element("x"))` is 0. The
shim is correct as written and the line stays.

`test/lib_mimic_xml_etree_elementtree.npy` therefore does not assert `len()` of
a Comment, with the absence named there and in the Makefile.

## Gate

`make test-nilpy` green + self-host byte-identical. A regression test wants
both tables: the four ways to lose a static type, and the four self-reference
shapes with the other-function control.
