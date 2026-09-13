---
slug: bug-n-a-staticmethod-or-classmethod-is-unreachable-through-a-class-held-as-a-value
title: a staticmethod or classmethod is unreachable through a class held as a value
summary: >
  `alias = gl; alias.sm(1)` raises `AttributeError: 'type' object has no
  attribute 'sm'` for a @staticmethod, and the same for a @classmethod, while
  `gl.sm(1)` spelled directly on the class works. Class ATTRIBUTES and INSTANCE
  methods both survive the same alias, so this is not "a class value loses its
  members" -- it is exactly the members that take NO INSTANCE. Cause measured:
  PyEmitClsAttrBinds publishes class attributes to a runtime registry keyed by
  the class's RTTI blob, which is what makes `alias.RENDERER` work, and nothing
  publishes METHODS, so a dynamic receiver holding a class finds nothing and
  falls through to pydynattr_no_method. [THAT CAUSE IS THE READ PATH AND IT IS
  NOT WHAT WAS WRONG WITH THE CALL. Corrected 2026-09-13 by measurement: the
  guard in PyParseVariantMethod is HOISTED ahead of every dispatch arm and asserts
  pyvar_is_objtag, so a VT_CLASSREF receiver was refused before any arm ran. The
  registry observation is true and belongs to reading the method as a VALUE, which
  is still refused -- see the residual section.] FIXED 2026-09-13 for the call:
  `alias.sget(1)` and `alias.cget(1)` now answer, lekkerzeilen's `--m0` gets two
  real glGetString results back from the driver, and the wall moved one line on.
track: N
type: bug
status: done
prio: 70
owner: frank-user
---

## What was measured

2026-09-13, at 2ee0eae8e. One class, one alias, eight rows, each row wrapped so
one failure does not mask the rest (the first version stopped at row 2 and I
could not see rows 3-8 at all).

    class gl:
        RENDERER = 7
        @staticmethod
        def sm(name):   return "S" + str(name)
        @classmethod
        def cm(cls, n): return "C" + str(n)
        def inst(self, n): return "I" + str(n)

    alias = gl

    row  spelling                  CPython   pxx
    1    gl.sm(1)                  S1        S1
    2    alias.sm(1)               S1        AttributeError: 'type' object has no attribute 'sm'
    3    gl.RENDERER               7         7
    4    alias.RENDERER            7         7
    5    gl.cm(1)                  C1        C1
    6    alias.cm(1)               C1        AttributeError: 'type' object has no attribute 'cm'
    7    gl().inst(1)              I1        I1
    8    alias().inst(1)           I1        I1

**Two of eight, and the pattern is the finding.** Through a class held in a
variable: a class attribute works (4), an instance method works (8, because
`alias()` constructs and the receiver is then an ordinary instance), and the two
members that take NO INSTANCE fail (2, 6). Spelled directly on the class all
four work, so nothing is wrong with staticmethods or classmethods as such.

The app's real route is an IMPORT, not a local alias, and it reproduces
identically in a three-file package:

    pkg/back.py   class gl: ... @staticmethod def sm(n)
    pkg/seam.py   from . import back
                  gl = back.gl
    imp.py        from pkg.seam import gl
                  gl.sm(1)        -> same AttributeError

## Cause

`PyEmitClsAttrBinds(ci)` (pyparser.inc) publishes each class ATTRIBUTE to the
run time as `pyclsattr_bind(<RTTI blob>, "name", @slot, kind)`, keyed on the
class's RTTI blob pointer. Its own comment says why it has to exist: a class
attribute is not stored on the class, each gets a hidden global, and *"a class
held as a VALUE has no class index at the point of the read, so nothing was left
for it to consult"*. That is the fix for
`bug-nilpy-class-attribute-through-a-class-reference-reads-garbage`, and it is
why row 4 passes.

**Nothing does the equivalent for methods.** A call through a class value
therefore reaches the runtime dispatcher, finds no entry, and
`pydynattr_no_method` raises with `TObject(obj).ClassName`, which for a class
object is `'type'` -- hence the message naming a type rather than the class.

## Why it matters now

`--m0` is the app's own seam test: a window, a context, a loop, a clean exit.
Under pxx it now gets FURTHER than this ticket's filing would suggest —
`platform.open_window(...)` returns, `win.set_vsync(True)` works, and
`backend : pxx` prints — and then dies on the next line, `gl.get_string(gl.RENDERER)`.
CPython on the same box runs it to completion: an NVIDIA GL 3.3 window,
1280x720, 345 frames in 5.8s at 60fps. So the control is green and the failure
is ours.

`lekkerzeilen/platform/_pxx.py` declares `class gl:` at line 139 as a pure
namespace of @staticmethods (`get_string` at 480, plus viewport, enable,
disable, depth_mask, read_pixels and more), and
`lekkerzeilen/platform/__init__.py:86` is `gl = _backend.gl`. Every GL call in
the app goes through that binding, so this single defect stands between the
window opening and anything being drawn in it.

## Shape of a fix, and the hazard it must avoid

Publish the no-instance methods to the same registry the attributes use, or a
sibling of it, so a dynamic receiver holding a class can resolve them.

**The thing that will bite, learned the hard way earlier the same day in
`bug-n-getattr-cannot-see-a-method-and-segfaults-through-a-dynamic-receiver`:**
whatever the registry hands back must be normalised to the FUNCTION-OBJECT ABI
(variant parameters, variant result). An unnormalised method returns its result
in a register while the caller expects the hidden-destination convention, and
the symptom is not a crash at the call -- it is an EMPTY STRING for a string
result, a SEGFAULT on return for an int, and correct behaviour for a method
returning None. That fix's four ruled-out hypotheses were all about REACHING the
method and none of them was the ABI, which cost a whole attempt. `PyMethodUsedAsValue`
is the function that decides normalisation; a new route that produces a callable
needs an arm there, or it will appear to work on exactly the rows that return
nothing.

## Not claimed

No census of how common the class-as-namespace idiom is outside this backend. It
is idiomatic for a C-API shim (it mirrors module shape without needing a module
per backend, which is the comment on that very line), so the population is
probably "every shim written this way", but that is an expectation and not a
measurement.

## Sharpened 2026-09-13, same evening — the fix has an exact precedent in the tree

Four more measurements, and together they turn "add an arm somewhere" into a
specified job. **I did not do it: this is parked, not half-done.**

### It is TWO sites, and the messages prove it

    alias.sm          read as a VALUE   "type object 'gl' has no attribute 'sm'"
    f = alias.sm; f(1)                  same
    getattr(alias, "sm")                same
    alias.sm(1)       CALLED            "'type' object has no attribute 'sm'"

The first three are `pydynattr_get_v`'s tag-11 branch (pylib.pas ~4919), which
asks `PyClsAttrRefGet`, then `__name__`, then raises naming the class. The fourth
is `pydynattr_no_method`, reached from the dispatcher the frontend builds. So the
READ path and the CALL path each lack no-instance methods, independently.

**The read path is the foundation.** If a classref read could produce the method
as a callable, rows 1 and 3 work immediately through the existing function-object
ABI, and the call path can then be fixed by routing its tag-11 case to
read-then-call rather than by teaching it a new kind of arm.

### An IMPORTED class is fine — so this is about the VALUE route only

    from pkg.cls import K
    K().inst()   WORKS      K.V   WORKS      K.sm(1)   WORKS

All three. A directly-imported class keeps its compile-time identity and
staticmethods resolve statically. The defect is confined to a class that has
become a VALUE (assigned to a name, or read off a module as
`gl = back.gl`). So no import machinery needs touching.

### The class-as-value feature is three-quarters built

    construct          alias()           WORKS
    class attribute    alias.V           WORKS  (via pyclsattr_bind)
    instance method    alias().inst()    WORKS
    no-instance method alias.sm()        MISSING   <- this ticket

That reframes the job: FINISH `feature-nilpy-class-as-a-value`, do not redesign
anything.

### The recommended route, and it mirrors a mechanism already in the tree

`PyEmitClsAttrBinds(ci)` already solves the identical problem for attributes: a
class attribute is not stored on the class, so the FRONTEND publishes
`pyclsattr_bind(<RTTI blob>, "name", @slot, kind)` per attribute at
class-definition time, and the tag-11 read consults that registry. It sidesteps
RTTI entirely.

Do the same for methods: an analogous `PyEmitClsMethBinds(ci)` emitting the
PROC ADDRESS of each @staticmethod / @classmethod, and a tag-11 read that returns
it as a callable. This is why it is the recommended route rather than a runtime
RTTI walk — **whether a no-instance method is reachable from the RTTI blob at run
time is the one thing I did NOT establish**, and the registry makes the question
moot exactly as it did for attributes.

### Why NOT to add an arm to PyParseVariantMethod, which was my first instinct

**[SUPERSEDED 2026-09-13, the same evening, by measurement — the invariant this
section is built on is FALSE, and the arm is what landed. Kept because the
reasoning is exactly the shape that nearly stopped the cheap fix, and because the
bad premise is instructive: it was read off a NAME.]**

That function (pyparser.inc 18129 onward, ~1270 lines) is built around
`selfArg`: the receiver is argument one, and overload re-resolution by arity,
`PyBindKwArgs`, `PyPackStarArgs` and the default fill all count positions
relative to it, dropping self from the count in three separate places. ~~**A
staticmethod has no self**, so a classref arm contradicts the invariant the
whole function is written on~~, and every dynamic method call in NilPy flows
through it. Landing a change there needs the full NilPy tier, not a quick gate.
The read-path route touches one Pascal function plus an emitter and leaves that
invariant alone.

**What the measurement says instead.** In NilPy a @staticmethod DOES have a slot
0 and it holds the CLASS. `UMthIsStatic` does not mean "no Self" — `UMthNoSelf`
means that — it means CLASS-LEVEL, and **both decorators ride `UMthIsStatic`**:
a classmethod declares `cls` and a static gets an injected `$clsrecv`
(`tyPointer`). So slot 0 is present in both cases and wants a class, which is
precisely what a VT_CLASSREF variant's payload already is. Far from contradicting
the function's invariant, the classref receiver SATISFIES it — the arm needs no
instance, no class cast, and no change to any of the three position counts,
because it bypasses the arity re-resolution entirely (one carrier, one proc).

`pasparser_lval.inc` had already written the same sentence from the other side
and I did not go and read it: *"a class method: Self is a real argument, so
passing the metaclass VALUE makes the dispatch dynamic for free."*

The section's last two claims survive and both held: it needs the full NilPy
tier, and it is every dynamic method call. What did not survive was a premise
taken from what `UMthIsStatic` is CALLED. A 1270-line function with a stated
invariant is the most expensive place to accept a name for the thing.

### The hazard, restated because it is what cost an attempt today

Whatever the registry hands back MUST be normalised to the function-object ABI.
`PyMethodUsedAsValue` is the gate, and this evening it grew its literal-getattr
arm (`PyModuleGetattrsLiteral`) for exactly this reason. A method published to a
registry and called back unnormalised does not crash at the call — it answers
`''` for a string, SEGFAULTS on return for an int, and behaves perfectly for a
method returning None. Any new publication route needs an arm there, or it will
pass every test whose methods return nothing.

### Not established

~~Whether a static/class method is reachable from the RTTI blob at run time~~ —
**settled 2026-09-13: the question does not arise on the route that landed.**
Nothing is recovered FROM the blob; the blob is passed straight into slot 0,
which is what the statically spelled `Gl.sget(1)` passes too. A classmethod's
`cls` binds to that same blob and it is correct — row B of the fixture returns
`C1` against CPython's `C1`. What remains unestablished: no census of the
class-as-namespace idiom outside this backend.


## RESOLUTION — 2026-09-13

### What landed

`compiler/pyparser.inc`, two sites, and `compiler/builtin/pylib.pas`, one:

1. **`PyClassLevelOnlyMeth(nm, outMmi)`** (new, before `PyParseVariantMethod`).
   True when `nm` is declared at class level by exactly one class — counted by
   distinct PROC, so an inherited method reported for a subclass and its parent is
   not two carriers — and as an ordinary instance method by none. Then a receiver
   of unknown tag has exactly one valid reading.

2. **The hoisted receiver guard** now asks `pyvar_is_classreftag` instead of
   `pyvar_is_objtag` when that holds. This is the whole defect: the guard sits
   AHEAD of every arm, so the function was unreachable for a class receiver no
   matter what the arms could do.

3. **A direct-call block**, placed deliberately BEFORE the arity re-resolution
   (which re-picks overloads by counting positions relative to an INSTANCE self,
   which this receiver is not). It passes `pyvarobj(vtTmp)` — the raw payload,
   i.e. the RTTI blob — as slot 0 with no class cast, then the user's arguments in
   binding order, then the proc.

4. **`pyvar_is_classreftag`** in `compiler/builtin/pylib.pas`: `pyvartag(v) = 11`.

### The hour this cost, and it is a "the name is not the thing" instance

The first version of the guard used **`pyvar_holds(v, 11)`**. `pyvar_holds` reads
like a tag test and is not one: it requires tag 7 and then asks which CONTAINER
class the object is (k = 1/2/3 for list/dict/bytes), so `pyvar_holds(v, 11)` is
**unconditionally False** and the widened guard refused every receiver. The
symptom was a change with proven-firing internals and zero behavioural effect —
`PyClassLevelOnlyMeth` returned True with the right proc, a probe proved the
direct-call block FIRED, and the program still raised. The fix for the bug
reproduced the bug. The forward declaration of `pyvar_is_classreftag` now carries
a comment saying `pyvar_holds` is NOT this test.

### Verification

- **Fixture:** `test/test_nilpy_a_class_held_as_a_value_reaches_a_class_level_method.npy`,
  11 rows, wired into `test-nilpy`.
- **Positive control, measured:** under **pin v408** rows A–E raise
  `AttributeError: 'type' object has no attribute <name>` and rows F–K pass. At
  HEAD all 11 match the `.expected`. The five rows that moved are exactly the five
  this fix is about.
- **CPython oracle:** rows A–I agree; J and K are the two labelled LIMIT rows.
- **Full NilPy tier**, not a quick gate, because `PyParseVariantMethod` is on every
  dynamic method call.
- **lekkerzeilen `--m0`:** prints `renderer : NVIDIA GeForce GTX 1660
  SUPER/PCIe/SSE2` and `gl : 3.3.0 NVIDIA 580.178.04` — two `glGetString` calls
  through `gl.get_string`, the call this ticket was filed for.

### What is still refused, and it is two tickets

- **The call path, two remaining shapes** — a name carried both at class level and
  as an instance method, and two distinct class-level carriers. Both want one
  unbuilt mechanism (a CLASSREF arm in the runtime arm chain, testing the RTTI
  blob the way the existing arms test `pyvarobj(v) is C`):
  `bug-n-a-class-level-method-through-a-class-value-is-refused-when-the-name-has-two-carriers`.
- **The READ path** — reading a class-level method off a class value as a VALUE
  rather than calling it, and `getattr(alias, "sm")`, both still raise
  `type object 'gl' has no attribute 'sm'`. That is where this ticket's original
  registry diagnosis applies, and it is a different mechanism.

### The wall that replaced it

`win.size` segfaults one line later:
`bug-n-a-bytearray-bound-to-a-c-pointer-parameter-passes-the-object-pointer-not-the-data`,
prio 80. A `bytearray` bound to a C pointer parameter passes the address of pxx's
{data pointer, length} descriptor rather than the data pointer, so a C function
that writes destroys the handle. The whole pxx platform backend is built on that
shape.

## Log
- 2026-09-13 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
