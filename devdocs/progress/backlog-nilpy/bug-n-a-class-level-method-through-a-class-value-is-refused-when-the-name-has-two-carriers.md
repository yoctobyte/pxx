---
slug: bug-n-a-class-level-method-through-a-class-value-is-refused-when-the-name-has-two-carriers
title: a class-level method through a class value is refused when TWO CLASSES carry it at class level
summary: >
  SHAPE (a) IS FIXED, 2026-09-13: `alias = Gl; alias.m(...)` now reaches a
  @staticmethod or @classmethod whose name is ALSO carried by other classes as an
  ordinary instance method, chosen by the receiver's runtime tag. That was the live
  wall on lekkerzeilen `--m0` -- `gl.clear()`, a @staticmethod on the `gl` namespace
  class and an instance method on three others -- and the demo now reaches its
  render loop.
  WHAT IS LEFT IS SHAPE (b): TWO DIFFERENT CLASSES declaring the same name at class
  level. `PyClassLevelCarrier` still refuses that, because choosing between two
  class receivers needs a blob-IDENTITY test (`pyvarobj(v) = <the RTTI blob of C>`)
  and the arm chain's existing tests are `pyvarobj(v) is C`, an INSTANCE test that
  cannot discriminate two classes. Row K of
  test_nilpy_a_class_held_as_a_value_reaches_a_class_level_method.npy asserts the
  refusal; CPython answers "A10" there. Nothing measured asks for it, which is why
  this is back at 40.
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
an instance method, beyond the one row below.

## The census, measured 2026-09-13 -- and it contradicts the paragraph above it

The text here used to read *"The shape that motivated the parent ticket -- a
class-as-namespace in a platform backend -- does not need this, which is why the
single-carrier case landed alone."* That was written the same day and it is false
for the program it names. With the bytearray/C-pointer defect fixed, lekkerzeilen
`--m0` gets a window, a GL 3.3 context, the renderer string and
`drawable : 1280x720`, and then stops here:

    Unhandled exception: AttributeError: 'type' object has no attribute 'clear'

`gl.clear()` (`lekkerzeilen/__main__.py:182`, and twice more in `app.py`) is a
@staticmethod on the `gl` namespace class at `platform/_pxx.py:453`. The name
`clear` is ALSO an ordinary instance method at `platform/_ctypes_backend.py:209`
and `wake.py:53`, and `PyClassLevelOnlyMeth` exits on the first instance carrier
it meets. So the class-as-namespace backend needs exactly this, and needs only
shape (a): ONE class-level carrier, any number of instance carriers.

That is the narrower fix and it is worth saying so: widening
`PyClassLevelOnlyMeth` to ignore instance carriers and adding ONE classref arm
clears the demo. Shape (b) -- two distinct class-level carriers -- still wants the
blob-identity test described above and nothing measured asks for it yet.

## See also

- `bug-n-a-staticmethod-or-classmethod-is-unreachable-through-a-class-held-as-a-value`
  -- the parent; the single-carrier call path, resolved 2026-09-13.
- `bug-n-a-class-level-method-read-off-a-class-value-as-a-value-is-refused`
  -- the READ path, a different mechanism (the attribute registry), same shape.

## SHAPE (a) RESOLVED 2026-09-13

`PyClassLevelOnlyMeth` was answering two questions at once and folding the second
into a refusal. Split into `PyClassLevelCarrier(nm, outMmi, anyInstance)`:

- exactly ONE class-level carrier (counted by distinct proc) decides whether a
  class receiver can be dispatched at all;
- `anyInstance` decides only whether the instance arm chain is needed BESIDE it.

`PyClassLevelOnlyMeth` is now one line over that, so the single-carrier direct
call is untouched.

Three changes in `PyParseVariantMethod`, and the middle one is the load-bearing
part the parent ticket warned about:

1. the hoisted guard is widened to `objtag OR classreftag` when the name has a
   class-level carrier AND instance carriers -- widening the arms alone changes
   nothing, because the guard runs first;
2. a CLASSREF ARM, added LAST so it is outermost:
   `pyvar_is_classreftag(recv) ? <the class-level method> : <the instance chain>`.
   Slot 0 takes `pyvarobj(recv)` -- the RTTI blob, which is what an injected
   `$clsrecv` or a declared `cls` wants and what a statically spelled `C.m(...)`
   passes. Missing arguments are filled from DEFAULTS exactly as a dual candidate's
   are, and the arm is DROPPED rather than fudged when the arity cannot be
   completed. The fill is not optional: `gl.clear()` writes no arguments and
   `clear(depth=True)` declares one;
3. the unkept-promise FIXUP, mirroring the str and float ones: if the guard was
   widened and the arm was then dropped on arity, restore the
   `pydynattr_no_method` raise for a tag-11 receiver.

### The fixup's positive control, measured

Row O of the fixture answers the same string before and after this fix, so on a
value comparison alone it is a guard that cannot fail. Its assertion class is a
CRASH. Measured by disabling ONLY the fixup and rebuilding: the fixture
SEGFAULTS at row O (rc=139), and every row from O onward vanishes -- so the diff
does see it, by absence. Without the fixup a tag-11 receiver passes the widened
guard, misses every `pyvarobj(v) is C` arm, and reaches the static class cast,
which dereferences an RTTI blob as an instance.

### Verified

- Fixture extended to 16 rows. Control under pin v408: A-E, J and L raise
  `AttributeError: 'type' object has no attribute <name>`; F-I, K, M, N, O, P pass
  there too and are regression guards. So SEVEN rows have moved across the two
  commits and J and L are the two this change owns.
- L/M/N are ONE call site (`viawipe(o)`) reached with a class value and two
  different instances, which is the claim in both directions: the arm must not
  steal an instance receiver and the chain must not steal a class one.
- `gate.sh quick` GREEN after a reviewed `--update` of the AST slot-write census
  (14 rows, every one an ordinary node-into-child-slot write for an existing kind,
  so `ASTLeftIsChild`/`ASTRightIsChild` need nothing).
- lekkerzeilen `--m0` no longer raises on `gl.clear()`; it reaches its render loop
  and stays there. NOT established: that frames are being SWAPPED. The loop prints
  its frame count only on a clean exit, and closing the window from outside failed
  (the session is Wayland, and forcing X11 then driving it with xdotool killed the
  process through its X connection rather than through the QUIT path -- my own
  interference, not a defect).
