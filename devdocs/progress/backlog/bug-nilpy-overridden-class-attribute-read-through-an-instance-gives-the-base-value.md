---
track: N
prio: 55
type: bug
summary: "NilPy: a class attribute overridden in a subclass reads the BASE's value through an instance — Derived().kind is 'base', while Derived.kind is correctly 'derived'. Silent wrong value on ordinary Python"
---

# An overridden class attribute reads the base's value through an instance

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-07, by a probe that could not compile until
  [[bug-nilpy-unbound-base-class-init-call-is-rejected]] was fixed earlier the
  same day. **Pre-existing, not a regression** — controlled by running the same
  repro on the PINNED binary, which predates every change in that session and
  gives the identical wrong answer.

## Measured

```python
class Base:
    kind = "base"
    def __init__(self, n):
        self.n = n

class Derived(Base):
    kind = "derived"
    def __init__(self, n):
        super().__init__(n)

print(Base(3).kind, Derived(4).kind)   # CPython: base derived   pxx: base base
print(Base.kind, Derived.kind)         # CPython: base derived   pxx: base derived
```

So the value is reachable and correct **through the class name**, and wrong
**through an instance**. The receiver's own class is not consulted; the read
resolves to the base's slot.

## Why the existing ticket does not cover it

[[bug-nilpy-class-attribute-unreachable-through-the-class-name]] (done) built
the shared-slot + per-instance-override model and its test covers *"inheritance
through the subclass NAME"* — the row that works. An instance read of an
attribute the subclass **re-declares** is the untested neighbour, and it is the
spelling ordinary code uses (`self.kind` inside a method is the same shape).

## The fork worth settling before implementing

A class attribute is a class-level GLOBAL, so an instance read compiles to a
global address. Two levels of fix, and they are not the same size:

1. **Static receiver class.** In the repro the receiver's static type IS
   `Derived`, so resolving the class-var by walking from the *receiver's* class
   rather than the declaring base would fix it — and `self.kind` inside a method
   too. Small, and covers the common case.
2. **Runtime receiver class.** A `Base`-typed variable holding a `Derived`, or a
   heterogeneous list walked in a loop, needs the read dispatched on the
   RUNTIME class. That is a different mechanism from a global address.

Doing (1) alone leaves (2) silently wrong, which is exactly the
`devdocs/dev/normalise-dont-special-case.md` trap — a second path that stays
broken. Worth deciding deliberately rather than taking (1) because it is
reachable: either land (1) *with* (2) filed and linked, or make (2)'s shape
diagnose rather than answer wrongly.

## Gate

Per-fix loop. A `.npy` test covering: the overridden attribute through an
instance and through the class name, `self.attr` read inside a base method on a
derived instance, a Base-typed binding holding a Derived, a heterogeneous list
walked in a loop, an attribute the subclass does NOT override (must still find
the base's), and a per-instance override on top — diffed against CPython with
`tools/pydiff.py`.
