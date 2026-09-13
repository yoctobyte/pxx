---
slug: bug-n-a-class-level-method-through-a-class-value-is-refused-when-the-name-has-two-carriers
title: a class-level method through a class value is refused when the name has two carriers
summary: >
  `alias = Gl; alias.sget(1)` now works for a @staticmethod or @classmethod whose
  name has exactly ONE class-level carrier in the module and no instance carrier.
  Two shapes are still refused with `AttributeError: 'type' object has no
  attribute <name>`: (a) the name is ALSO an ordinary method on some other class,
  and (b) two different classes declare it at class level. Both are the same gap
  -- `PyClassLevelOnlyMeth` admits a name only when the reading is unique, because
  the runtime arm chain in `PyParseVariantMethod` has no CLASSREF arm: its arms
  test `pyvarobj(v) is C`, an INSTANCE test, so there is nothing to select
  between two class receivers with. Rows J and K of
  test_nilpy_a_class_held_as_a_value_reaches_a_class_level_method.npy assert both
  refusals, so the limit is in the suite and not only here.
track: N
type: bug
prio: 40
owner: unassigned
status: backlog
---

## What was measured

2026-09-13, at the tree that landed the single-carrier fix (binary c139938e5476).
CPython is the oracle; both rows are ordinary Python it accepts.

    class StatFirst:
        @staticmethod
        def both(n):     return "stat" + str(n)

    class InstLast:
        def both(self, n): return "inst" + str(n)

    class TwiceA:
        @staticmethod
        def twice(n):    return "A" + str(n)

    class TwiceB:
        @staticmethod
        def twice(n):    return "B" + str(n)

    def viadyn(o, n):  return o.both(n)
    ta = TwiceA

    row                            CPython   pxx
    viadyn(InstLast(), 8)          inst8     inst8     <- works, and must keep working
    viadyn(StatFirst, 9)           stat9     AttributeError: 'type' object has no attribute 'both'
    ta.twice(10)                   A10       AttributeError: 'type' object has no attribute 'twice'

`TwiceA.twice(10)` spelled on the class LITERALLY is fine — that never reaches the
dynamic path at all. It takes an alias to expose this.

## Why the landed fix stops where it does

`PyClassLevelOnlyMeth(nm, outMmi)` returns True only for a name with exactly one
class-level carrier (counted by distinct PROC, so inheritance does not count
twice) and ZERO instance carriers. When it says True, the receiver has only one
valid reading and `PyParseVariantMethod` emits a direct call, passing the
variant's payload -- the RTTI blob -- as slot 0.

When it says False the function falls back to the old behaviour, which asserts
`pyvar_is_objtag` in a HOISTED guard and therefore refuses a class receiver
before any arm runs. That is correct in the sense that it refuses rather than
guessing, and wrong in the sense that CPython answers.

## The fix, and it is one mechanism for both rows

Give the arm chain a CLASSREF arm. Today each arm is

    if pyvarobj(v) is SomeClass then <call SomeClass's method>

an INSTANCE test, which cannot discriminate two class receivers because neither is
an instance of anything. The classref equivalent is a blob-identity test:
`pyvarobj(v) = <the RTTI blob of SomeClass>`, emitted from the same place the
statically spelled `SomeClass.m(...)` gets its blob. With that, both rows fall out
of the existing generator:

- two class-level carriers -> two classref arms, chosen by blob identity;
- a name carried both ways -> a classref arm for the static reading and the
  ordinary objtag arm for the instance reading, in one chain.

`PyClassLevelOnlyMeth` then narrows to an OPTIMISATION (one carrier, skip the
chain) rather than a gate, and the direct-call block it guards can stay exactly
as it is.

## What to be careful of

**The hoisted guard is the thing that bites.** It sits ahead of every arm, so
widening the arms without widening the guard changes nothing -- and the guard
cannot simply be dropped, because the arms dereference the payload as an instance.
It has to become "objtag OR classreftag", with each arm asserting its own tag.
`pyvar_is_classreftag` already exists in `compiler/builtin/pylib.pas` for this.

**Do not reach for `pyvar_holds` for the tag test.** It requires tag 7 and then
asks which CONTAINER class the object is (k = 1/2/3 for list/dict/bytes), so
`pyvar_holds(v, 11)` is unconditionally False. It reads like a tag test and is
not one; it cost an hour on the fix that landed, producing a change with no
behavioural effect and a guard that refused every receiver.

**Every dynamic method call in NilPy flows through this function.** Full NilPy
tier, not a quick gate.

## Not established

No census of how often a real program carries one name both at class level and as
an instance method. The shape that motivated the parent ticket -- a
class-as-namespace in a platform backend -- does not need this, which is why the
single-carrier case landed alone.

## See also

- `bug-n-a-staticmethod-or-classmethod-is-unreachable-through-a-class-held-as-a-value`
  -- the parent; the single-carrier call path, resolved 2026-09-13.
- `bug-n-a-class-level-method-read-off-a-class-value-as-a-value-is-refused`
  -- the READ path, a different mechanism (the attribute registry), same shape.
