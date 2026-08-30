---
track: N
prio: 65
type: bug
blocked-by: []
summary: "`a, b = X(), Y()` binds EVERY target to the whole right-hand list instead of unpacking it, when the values' type defines __iter__ or __getitem__. The swap idiom `p, q = q, p` is hit. A NAMED right-hand side (`a, b = tup`), a call (`a, b = f()`) and for-loop targets are all correct, and so is any class without __iter__/__getitem__ -- so it takes a container-ish class AND an inline tuple display to trigger. Silent: downstream sees a list, and a longer program segfaults."
---

# Tuple unpacking of an inline tuple does not unpack values whose type is iterable

- **Type:** bug (Nil-Python frontend) — **Track N**.
- **Filed:** 2026-08-30 by frankB, from
  [[feature-b-sweep-mimic-shims-against-cpython]] phase 2, while extending the
  `xml.etree.ElementTree` differential.
- Measured at pin **v395** (`stable_linux_amd64/default/pinned`), CPython 3.12
  as the oracle. Every row is from a run.

## Repro

```python
from xml.etree.ElementTree import Element
a, b = Element("a"), Element("b")
print(type(a).__name__, type(b).__name__)
```

| | |
| --- | --- |
| CPython | `Element Element` |
| pxx | `list list` |

Both names hold the **whole right-hand side** — `len(a)` is 2 and `a[0]` is
`Element("a")`. Nothing is raised at the assignment; the wrong binding is
discovered later, as an `AttributeError: 'TPyList' object has no attribute
'tag'`, or not at all.

## The trigger is `__iter__` or `__getitem__` on the VALUE's type

Four classes differing only in which protocol methods they declare, one
`a, b = C(1), C(2)` each:

| the class declares | pxx | CPython |
| --- | --- | --- |
| nothing | `Plain Plain` | `Plain Plain` |
| `__len__` | `WithLen WithLen` | `WithLen WithLen` |
| **`__iter__`** | **`list list`** | `WithIter WithIter` |
| **`__getitem__`** | **`list list`** | `WithGetitem WithGetitem` |

`__len__` alone is fine, which is what makes this a decision about
*iterability* rather than about sequence-ness in general. `Element` declares
all three, which is why the etree shim was where it surfaced.

## ...and only for an INLINE tuple display

Same `It` class (declares `__iter__`) throughout:

| assignment | pxx | CPython |
| --- | --- | --- |
| `g, h, i = It(7), It(8), It(9)` | **`list list list`** | `It It It` |
| `p, q = q, p` (the swap idiom) | **`[, ]`** — both `.v` empty | `[11, 10]` |
| `tup = (It(3), It(4))`; `c, d = tup` | `It It` | `It It` |
| `lst = [It(5), It(6)]`; `e, f = lst` | `It It` | `It It` |
| `def pair(): return It(20), It(21)`; `r, s = pair()` | `It It` | `It It` |
| `for m, n in [(It(30), It(31))]:` | `It It` | `It It` |

So the unpack machinery itself is fine — every path that unpacks a value
arriving from *somewhere else* is right. It is specifically the form where the
tuple is written out at the assignment that skips the unpack and assigns the
built list to each target. The number of targets does not matter (2 and 3 both
fail).

**The swap row is the one to care about.** `p, q = q, p` is not an exotic
construct, it is how Python spells a swap, and here it silently replaces both
variables with a list.

## Severity

p65, and the reasons compound:

- **Silent.** No error at the assignment. The value that lands is a valid list,
  so `len`, indexing and iteration all succeed on it and answer about the
  wrong object.
- **Common shape.** `a, b = X(), Y()` and `p, q = q, p` are everyday Python.
- **Common type.** Any class with `__iter__` or `__getitem__` — which is what
  every container-ish class in a library has, and what `Element` has.
- **It escalates.** A longer program built on the mis-binding **segfaults**:
  `up6.npy`, which chained the swap after several other unpacks of the same
  class, died with SIGSEGV rather than an AttributeError. The mis-binding is
  the root; the crash is downstream of it and its location is not stable.

## Sibling — check both arms before closing

[[bug-n-a-tuple-unpacking-assignment-does-not-box-a-callable-value]] (N, p55)
is the same statement form with a different value kind: `a, b = lambda ..., lambda ...`
unpacks but leaves each target unboxed, so `a(1)` is not callable. Two defects
in one construct is the double-case smell from
`devdocs/dev/normalise-dont-special-case.md` — **grep for the sibling before
closing either.** If the unpack path builds its own per-target stores rather
than reusing the single-target assignment path, both are consequences of that
one divergence and one fix closes both. Do not assume it; that ticket's own
cause section is explicitly marked unverified, and two recent N tickets named
the wrong mechanism.

## Suggested first look

The discriminator is compile-time: `WithLen` works and `WithIter` does not,
with identical call sites, so the frontend is deciding the shape of the
statement from the RHS element type. Look at where the unpacking assignment
decides between "the RHS is one iterable to spread" and "the RHS is a tuple of
N values" — the inline-display case appears to take the first branch and then
assign the un-spread list to every target. `PXXDBG=n.locals` and
`a.ast:<proc>` on the three-line repro should show which branch was taken.

## What it broke

`test/lib_mimic_xml_etree_elementtree.npy`'s extension used
`a, b, c = Element("a"), Element("b"), Element("c")` to build a fixture — the
obvious spelling — and every child came out tagless. The differential is
written with separate `x = Element(...)` statements instead, with a comment
pointing here, so it does not encode the workaround silently.

## Gate

`make test-nilpy` green + self-host byte-identical. A regression test wants all
six rows of the second table, because the point of the finding is that five of
them are right.
