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
  falls through to pydynattr_no_method. THIS IS THE LIVE BLOCKER ON THE
  LEKKERZEILEN WINDOW PATH: the pxx platform backend declares `class gl:` as a
  namespace of @staticmethods, the seam re-exports it as `gl = _backend.gl`, and
  `--m0` now OPENS A WINDOW under pxx and dies on the first `gl.get_string(...)`.
track: N
type: bug
status: backlog
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
