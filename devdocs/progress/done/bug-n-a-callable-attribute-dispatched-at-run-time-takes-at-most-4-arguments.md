---
slug: bug-n-a-callable-attribute-dispatched-at-run-time-takes-at-most-4-arguments
title: a callable attribute dispatched at run time takes at most 4 arguments
summary: >
  FIXED. A CALLABLE FIELD (not a method) called with five to eight arguments on
  a DYNAMICALLY-TYPED receiver was refused. The cap was FOUR in TWO independent
  spellings, and fixing either alone leaves the other: pyparser.inc's
  PyVariantFieldCallArm, which refuses at COMPILE time when the field's owning
  class is a visible candidate, and pyeval.pas's PyDynMethL, which raises at RUN
  time when no class declares the field at all. Both stopped where the
  pyvar_callv ladder stopped when they were written -- and that ladder HAS rungs
  5..8, added later the same day at 2b7068dd7 for the star-unpack path, so both
  caps were stale comments rather than decisions. No list-taking pyvar_callvl
  was needed; this ticket's own prescription was wrong about the cost. The
  ceiling is now EIGHT, structural (an indirect call needs a static arity), and
  refused by name with the count on both routes.
track: N
type: bug
prio: 40
owner: unassigned
status: done
---

## How it was reached

Not by a report. Lifting the frontend's 4-argument cap on run-time dispatch
(`MAX_DYN_ARGS`, so lekkerzeilen's `gl.tex_image_2d(target, fmt, w, h, fmt,
data, level=at)` could compile) made an arm REACHABLE that could not previously
be entered with five arguments: PyDynMethL's fallback for a receiver whose
attribute is a callable value, not a method.

`case nargs of 0..3: ... else pyvar_callv4(...)` was exactly right while the
frontend capped at four — `else` could only mean four. With the cap lifted it
would have meant "five or more, silently pass the first four", which is the
plausible-wrong-value trade the cap's own comment was written to avoid. So it
raises instead, and this ticket is the honest record of what that costs.

## Repro

A callable FIELD, not a method, on a receiver from another module:

```python
# holder.py
class Box:
    def __init__(self):
        self.thing = lambda a, b, c, d, e: a + b + c + d + e

def make():
    return Box()
```

```python
import holder
o = holder.make()
print(o.thing(1, 2, 3, 4, 5))
```

CPython prints 15. pxx raises
`thing() is dispatched at run time through a callable attribute, which takes at
most 4 arguments`.

## The fix

`pyvar_callv` needs a list-taking form the way `pydyn_meth` just got one —
`pyvar_callvl(cb, args: TPyList)` — and then PyDynMethL's callable arm loses its
`case` entirely. Both `pyvar_callv_kw` and the rungs stay as wrappers, for the
reason the pydyn rungs stayed: they are a public builtin interface.

Note the neighbouring refusal is a DIFFERENT one and is not this ticket: a
KEYWORD argument through a callable field is refused because there are no
parameter names to bind against, which is correct and intended.

## Resolution (2026-09-18)

**The repro in this ticket does not reproduce, and never did.** `o =
holder.make()` then `o.thing(1, 2, 3, 4, 5)` prints 15 on the PINNED, unfixed
compiler: the frontend types `o` from the call and dispatches STATICALLY,
reaching neither capped arm. A fixture written to that shape passes before the
fix -- the `ucycle_b` failure mode CLAUDE.md warns about, caught here by running
the negative control before committing rather than after, which is when it feels
like verification.

**THE RECEIVER HAS TO ARRIVE THROUGH A CONTAINER FOR EITHER ARM TO BE ENTERED.**
That sentence is the reproducer; this ticket's own was not. (A parameter with no
single inferable call site does it too.)

**Two spellings, and grepping for the construct does not relate them.** With the
receiver reached through a list, the observable is not this ticket's title at
all -- it is a COMPILE error, `.c5() — a callable field with no signature must
be variant-typed to be called on a dynamically-typed value`, from
PyVariantFieldCallArm. That message is true of a POINTER field and a false lead
about this one: a variant callable field has no signature at FOUR either, and
four compiles. The run-time message this ticket is named for needs a third
shape -- an attribute set on an instance whose class declares no such field, so
there is no candidate class and the lookup happens on the receiver. Measured,
both routes, 4 through 9 arguments, pinned versus fixed.

**The ceiling refusals.** Past eight, the candidate-class route used to fall
through to the pointer-field arm and report the `no signature` message, sending
the reader off to annotate a field whose annotation was never what decided it.
It now names the ceiling and the count, as the run-time route does. Both are
asserted in the Makefile.

**Unmasked, NOT caused, by this fix:** `self.cb = Tagged(tag).m5` where `tag` is
a PARAMETER does not register `cb` as a field at all, falls to the run-time
route, and dies with `object is not callable` -- at ONE argument, on the pinned
compiler, identical before and after. Its own ticket:
bug-n-a-bound-method-stored-in-a-field-from-a-parameterised-receiver-is-not-callable

Fixture `test/test_nilpy_callable_field_wide_arity.npy` (+ `callablefield_mod.py`)
covers both routes, all four carrier families, a second candidate class, and
both ceilings. It is refused by the pinned compiler and byte-identical to
CPython on the fixed one.

## Log
- 2026-09-18 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 0560e7b50.

## The general lesson: when you extend a ladder, grep for who counted its old top

This is not two authors drifting apart over months. `pyvar_callv5..8` landed at
2b7068dd7, later the SAME DAY as 95e7eb26e, and left TWO consumers behind within
hours. Neither consumer names the ladder and the ladder names neither consumer,
so no grep for the construct relates them -- the sibling-is-a-spelling case from
`normalise-dont-special-case.md`, arriving through a shared numeric CONSTANT
rather than through a shared shape.

The compile-time arm is the nastier of the two because its diagnostic argues
AGAINST the real cause: a fifth argument was reported as a MISSING SIGNATURE,
and a reader who believes it goes off to annotate a field whose annotation was
never what decided anything -- four arguments compile with the same missing
signature.

TRIGGER FOR PROMOTION TO CLAUDE.md, recorded rather than acted on. This met the
MERIT test and has NOT met the RECURRENCE one: it is a single subsystem -- the
pyvar_callv ladder and its two consumers -- and CLAUDE.md promotes on a SECOND
INDEPENDENT subsystem, not on quality, because merit-based promotion is how that
file reached 72KB the first time.

**If a second independent subsystem shows a consumer left behind by a WIDENED
NUMERIC BOUND, it is promoted as a STRENGTHENING of the existing
sibling-is-a-spelling rule -- an extension sentence, not a new neighbour.**

What it would strengthen, and why the existing rule does not already cover it:
CLAUDE.md says to grep for the other spelling's HANDLER. That does not find this
class. A consumer that merely stopped at four is not a handler for anything --
it names no ladder, contains no shared construct, and reads as ordinary correct
code. The actionable form is the one this ticket found: WHEN YOU EXTEND A LADDER,
GREP FOR WHO COUNTED ITS OLD TOP.
