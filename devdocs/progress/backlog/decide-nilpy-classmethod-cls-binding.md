---
track: U
prio: 40
type: decide
blocked-by: []
summary: "@classmethod is refused by name. The machinery is closer than its ticket says — @staticmethod already injects a hidden $clsrecv at slot 0 and the dispatch already passes A class there — so the only open question is WHICH class that is at run time for an inherited method reached through an instance, and whether a `cls` that is the statically-known class is acceptable or must be refused until it is the runtime one."
---

# `@classmethod`: which class does `cls` bind to?

Filed from Track A+N while clearing the N queue, per the escalate-don't-guess
rule. [[feature-nilpy-staticmethod-and-classmethod]] is the work ticket;
`@staticmethod` half of it is DONE and `@classmethod` is refused by name:

    Nil Python: @classmethod is not supported yet — its `cls` receiver is not
    modelled, and binding it to the declaring class would be silently wrong in
    a subclass.

## Why this is a decision and not just work

Reading the code, the mechanism is closer than that refusal implies.
`@staticmethod` does **not** simply drop the receiver — it injects a hidden
`$clsrecv` parameter at slot 0 and sets `UMthIsStatic`, which is Pascal's
`class procedure` flag, and the comment at that injection says every call path
consulting it "passes the CLASS as parameter 0 (that is what makes the
metaclass idiom work)". A `@classmethod` is then the same shape with the
parameter NAMED — the user's own `cls` — instead of hidden.

So the implementation is small. What is not settled is the SEMANTICS of that
slot, and getting it wrong is the silent kind:

```python
class Base:
    @classmethod
    def make(cls):
        return cls()

class Derived(Base):
    pass

Derived.make()      # CPython: a Derived
b: Base = Derived()
b.make()            # CPython: a Derived — the RUNTIME class, not Base
```

`Derived.make()` is answerable from the receiver expression at compile time.
`b.make()` is not: it needs the instance's runtime class, and whether the
existing static-dispatch path passes that or the statically-known one was not
measured — it is the whole question.

## The options

1. **Ship it only where the class is statically known**, and refuse a
   classmethod reached through an INSTANCE by name. Honest, small, and covers
   the common `Cls.factory()` idiom. The cost is a diagnostic on a shape
   CPython accepts.
2. **Ship it everywhere, binding `cls` to whatever slot 0 already carries.**
   If that is the runtime class, this is simply correct and there is nothing to
   decide. If it is the compile-time class, `b.make()` silently builds a Base —
   the failure mode this dialect refuses elsewhere.
3. **Keep refusing** until the runtime-class receiver is modelled properly.
   Status quo; costs nothing but leaves an ordinary Python idiom unavailable.

## What would settle it

One measurement, not an argument: make slot 0 readable from a NilPy body (a
classmethod returning `cls.__name__`, or `cls()` and then `type(x).__name__`)
and call it four ways — `Base.make()`, `Derived.make()`, through a Base-typed
instance holding a Derived, and through a variant receiver. Whoever picks this
up should do that FIRST; if the runtime class arrives, option 2 is not a
trade-off at all and this ticket dissolves.

Note the second half, which is independent: `cls()` — CONSTRUCTING through a
class held as a value — has its own gap
([[bug-n-a-type-name-is-not-a-first-class-value]], unfinished). A `cls` that
binds correctly but cannot be called is a classmethod that only works for
`cls.CONSTANT` and `cls.other_static()`, which may still be worth shipping, and
that is part of the same call.
