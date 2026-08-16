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

## Material 2026-08-14 (Track T) — the Pascal side already does the right thing

Not the measurement this ticket asks for, and does not settle it. But it removes
one worry: **the runtime machinery exists and is proven**, so if the NilPy
measurement comes back "compile-time class", that is a wiring problem rather than
a missing capability.

`cls` is precisely a Pascal **class reference** (`class of TBase`), and a
`class function` receives one implicitly as `Self`. Measured in pxx:

```pascal
type TBaseClass = class of TBase;
c := TDerived;
c.Who     -> TDerived     { virtual class-method dispatch through a class ref }
o := c.Create;
o.ClassName -> TDerived   { polymorphic construction }
```

and for the inherited case, without any class reference at all:

```
TBase.Who    -> TBase
TDerived.Who -> TDerived   { inherited class function, called on the descendant }
d.Me         -> TDerived   { instance method, Self is the instance }
```

**Both reference implementations already agree**: a Pascal `class function` and a
Python `@classmethod` bind to the class the call was made ON, not the class the
method was declared IN. So there is no semantic fork to decide — only the
question of what our NilPy dispatch actually passes.

That makes **option 1 look like a compromise nobody needs**: refusing the
instance-reached shape would be paying a diagnostic to avoid a problem the
underlying machinery does not have. Still contingent on the measurement.

### Also worth noting for whoever picks it up

Pascal overloads `Self` — the instance in a method, the class in a `class
function` — where Python splits it into `self` and `cls`. So the lowering target
for `cls` is the class-function `Self`, not the instance one, and the two are
distinguished by the kind of method rather than by the identifier.

---

# MEASURED 2026-08-16 — the measurement was done; the ticket dissolves

This ticket said: *"What would settle it — one measurement, not an argument […]
if the runtime class arrives, option 2 is not a trade-off at all and this ticket
dissolves."* Done, four ways. **The runtime class arrives.**

## 1. The dispatch already passes the RUNTIME class — in the source, not inferred

`compiler/parser.inc:6900-6907`, the arm taken when a `UMthIsStatic` method is
reached through an instance:

```pascal
if UMthIsStatic[mmi] then
begin
  { A CLASS method reached through an INSTANCE: `obj.ClassMethod(...)`. FPC
    allows it, and Self is the instance's RUNTIME class -- not the static type
    of the variable -- so it comes from __pxxRttiOf(obj), not a fixed
    AN_CLASSREF. }
  mselfArg := GenMakeRttiOfCall(node);
```

`__pxxRttiOf(obj)` is the instance's runtime class by construction. This is
exactly the `b.make()` case the ticket could not settle, and it was already
handled — deliberately, with the reasoning written at the site.

So **option 2 is simply correct**, on the ticket's own terms, and options 1 and
3 are refusing a problem that does not exist.

## 2. NilPy already resolves the runtime class through an inherited method

```python
class Base:
    def who(self):  return type(self).__name__
class Derived(Base): pass
Derived().who()      # pxx: 'Derived'   CPython: 'Derived'
Base().who()         # pxx: 'Base'      CPython: 'Base'
```

`self.__class__.__name__` agrees. The capability is not hypothetical in NilPy
either — it is the same shape `cls` needs, already working.

## 3. `cls()` — polymorphic construction — already works

The ticket flags this as an independent blocker: *"a `cls` that binds correctly
but cannot be called is a classmethod that only works for `cls.CONSTANT`."*
Measured, both forms construct:

```python
k = type(self); k()        # -> Derived     (class value from type())
k = Derived;    k()        # -> Derived     (bare type NAME as a value)
```

## 4. The blocker cited for that is CLOSED

[[bug-n-a-type-name-is-not-a-first-class-value]] is referenced here as
"unfinished". It is in **`done/`**, and the measurement above confirms it: `A =
B` then `A()` was its headline failing row and it now works. That reference is
stale and is the only thing that made the second half look open.

## Disposition

**Closed as measured, not decided.** There was never a semantic fork — the note
already in this ticket established that Pascal `class function` and Python
`@classmethod` agree on binding to the class the call was made *on*, and the
remaining question was only what our dispatch passes. It passes the right thing.

What is left is ordinary **Track N** work on
[[feature-nilpy-staticmethod-and-classmethod]]: name the slot-0 parameter `cls`
instead of the hidden `$clsrecv`, and lift the by-name refusal. The two-pass
agreement warning at `pyparser.inc:28884` applies unchanged — both passes inject
the parameter and a disagreement is a silent ABI mismatch, so the named form
must be injected in both places exactly as the hidden one is.

One check left for the implementer, not a blocker: `__pxxRttiOf(obj)` yields the
runtime class as an RTTI value, and §3 shows a class value from `type()`
constructs — so `cls()` inside an instance-reached classmethod is strongly
indicated to work, but confirm it directly rather than on this inference.

### Method note

Three of the four facts above were readable from the tree in minutes, and the
decisive one is a comment sitting at the call site describing precisely the
scenario the ticket called unmeasured. The ticket was filed correctly under
escalate-don't-guess — but escalation is for questions the *code* cannot answer,
and this one could. Read the dispatch before filing the fork.
