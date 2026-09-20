---
slug: bug-n-an-unused-import-edge-makes-a-method-receive-an-instance-of-the-wrong-class
type: bug
track: N
prio: 75
status: open
summary: "Adding an import of a name that is NEVER REFERENCED makes a method receive an instance of the WRONG CLASS as self — `from .world import Grid` in wind.py, with Grid unused, kills the demo with \"'World' object has no attribute 'flow'\" where flow is a field of Environment, so a World is arriving as self inside an Environment method. CPython runs the identical source. Same registration-order family as the import-closure ticket and the OPPOSITE direction — that one is FIXED by adding an edge, this one is CAUSED by adding one, which makes it a hazard for that ticket's own implementation."
---

# An unused import edge makes a method receive the wrong class as `self`

Reported by lekkerzeilen-7a 2026-09-20 (`530ba53`), found while running the
attribution that refuted the performance hypothesis on
`feature-n-register-the-class-shells-of-the-import-closure-before-parsing-any-body`.

## What happens

Adding `from .world import Grid` to the top of `wind.py` — **with `Grid` never
referenced anywhere in that module** — kills the program with:

    AttributeError: 'World' object has no attribute 'flow'

`flow` is a field of `Environment`. So a `World` instance is arriving as `self`
inside an `Environment` method: the receiver is an object of the wrong class and
the field read lands at whatever that offset holds. CPython runs 250 frames on
the identical source.

The edges in `sim.py` and `rig.py` are fine on their own. **The `wind.py` edge
alone is sufficient to break it.**

## Why the prio is 75 and not lower

- It is a WRONG OBJECT, not a wrong value: a method body running with a
  foreign instance as `self`. Every field read and write in that body is at a
  foreign offset. The AttributeError is the lucky outcome, not the
  characteristic one.
- The trigger is **adding an import that does nothing.** No call site changes,
  no name is used, nothing in the program references the imported class. There
  is no edit a reader could look at and predict this from.
- It blocks measurement of the hottest dispatch site in the demo
  (`canopy.contains()`, 1112 calls per frame, 69% of all dynamic dispatches),
  because the import edge that would resolve it statically is exactly the edit
  that triggers this.

## THE REASON THIS MATTERS TO THE IMPORT-CLOSURE TICKET, AND IT IS A HAZARD NOT A HINT

`feature-n-register-the-class-shells-of-the-import-closure-before-parsing-any-body`
proposes registering the class shells of the whole import closure before any
body is parsed. **That is, in effect, giving every module the visibility that an
explicit import edge gives it** — which is the operation that triggers this bug
when done by hand in one module.

So the two tickets are the same family pulling in opposite directions: one is
FIXED by adding an edge, the other is CAUSED by adding one. **Whoever implements
the closure registration must reproduce this first and understand it**, or the
fix may deliver this failure across a whole program at once, as a wrong object
rather than a diagnostic. A green tier would not necessarily catch it: the
condition needs several modules and a class-name population that a fixture
author has no reason to construct.

## NOT REDUCED

7a could not reduce it below the demo and did not locate the failing call site.
Per the tree's own rule, two failed reductions in this family mean the next
attempt should run candidates against the demo rather than reduce further —
mechanism from whoever has the source, verdict from whoever has the failing
tree. The demo is the artefact; the trigger is a one-line import.

## What would retire this

`from .world import Grid` in `wind.py`, unused, with the demo running its 250
frames and the value parity intact — and a fixture pinning the general shape
once the mechanism is known, since the general shape is what the closure ticket
will exercise everywhere.
