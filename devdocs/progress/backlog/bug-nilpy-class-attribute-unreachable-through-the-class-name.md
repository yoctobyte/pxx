---
track: N
prio: 65
type: bug
---

# `C.attr` on a class attribute: "class method not found"

- **Type:** bug (NilPy frontend gap — loud) — **Track N**
- **Found:** 2026-08-02, by a differential sweep against the CPython oracle.

## Measured

```python
class C:
    count = 0
print(C.count)          # error: class method not found: count
C.count = 5             # same
```

and inside a method, which is the idiom that matters:

```python
class C:
    count = 0
    def __init__(self):
        C.count += 1    # error: class method not found: count
```

**Every** access through the CLASS NAME fails — read, write, augmented, at
module level or inside a method.

## What DOES work

```python
class C:
    n = 5
c = C()
print(c.n)              # 5     via an INSTANCE
print(C().n)            # 5
class D:
    n = 7
    def get(self):
        return self.n   # 7     via self
a, b = C(), C()
print(a.n, b.n)         # 5 5   shared read
```

So class attributes exist and read correctly through an instance. Only the
`ClassName.attr` route is missing — and with it the counter/registry idiom,
which is the main reason to write a class attribute at all.

## Cause — TWO parts, and they are not equally hard

**1. The lookup never checks.** `parser.inc:4399` handles `ClassName.member`:
it tries methods, then class-ref operations (`InheritsFrom`, `ClassName`), then
errors. It never consults the class-attribute storage. Proof that this is a
real, separate half: an attribute with a NON-literal initialiser DOES get a
hidden global (`PyClsAttrGlobalName` → `$clsattr.<Class>.<name>`, built by
`PyEmitClassAttrExpr`), and `C.n` fails for it anyway:

```python
class C:
    n = 2 + 3        # gets a real global
print(C.n)           # still: class method not found: n
```

So for non-literal initialisers this is a **lookup-only fix**: fall back to
`FindSym(PyClsAttrGlobalName(ci, fieldName))` before erroring.

**2. A LITERAL initialiser has no storage to find.** `count = 0` is folded as a
constant into the field default — `PyEmitClassAttrExpr`'s own comment says the
single-literal case "is the folded-constant case the pre-pass already took". So
there is no global to point at, and `C.count = 5` has nowhere to write.

Making the common case work therefore needs literal class attributes promoted to
real storage, which is the risky half: it changes how every class attribute is
laid out and interacts with dataclass defaults (`PyDc*`) and instance init.

## Suggested order

Land **1** alone first — it is small, it is measurable (`n = 2 + 3` starts
working), and it cannot regress the literal path because that path errors today
either way. Then do **2** behind the full gate, with dataclass defaults
explicitly in the test set.

## Also found here

`from typing import ClassVar` fails to parse (`unexpected token`), so the
ClassVar-annotated route — which `PyRegisterClassMembers` explicitly supports
and registers via `FindClassVar` so that "ClassName.name resolves" — is
unreachable from NilPy source. Worth checking as part of 1, since that registry
is the other place `ClassName.attr` could resolve from.

## Gate

A `.npy` diffed against CPython covering: read/write/augmented `C.attr` at
module level and inside a method; the counter idiom incrementing across several
constructions; literal and non-literal initialisers; that instance reads still
see the class value and that assigning through an INSTANCE (`c.attr = ...`)
creates an instance attribute without disturbing the class one (Python's rule);
and a dataclass with defaults as a regression control.
