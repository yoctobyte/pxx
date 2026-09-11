---
slug: bug-n-an-attribute-read-through-a-class-bound-to-a-variable-gives-a-raw-address
track: N
type: bug
prio: 80
status: backlog
owner: ""
created: 2026-09-11
found: 2026-09-11
found-by: frankZ
tags: [nilpy, values, silent-wrong-value, lekkerzeilen]
blocked-by: []
summary: "SPLIT OUT OF bug-n-a-class-reached-through-a-unit-alias-is-not-a-value on 2026-09-11, which held two bugs on two axes. This is the SILENT arm: `w = SomeClass` then `w.V` answers a RAW ADDRESS (~5.5e6) instead of the class attribute, with no diagnostic and exit 0. The other arm is a refusal on METHOD CALLS and is import-free; this one is import-dependent and returns a wrong VALUE, which is worse in kind. THE TRIGGER IS NOT WHAT EITHER OF THE FIRST TWO STATEMENTS SAID, and frankZ corrected their own at 201131b40: it needs (a) a binding name DIFFERENT from the class's own name AND (b) ANY construct preceding the class in the declaring module -- a docstring counts. Binary, not proportional: one preceding construct and two give the IDENTICAL value, so it is not a field index shifted by the number of preceding names, which was the first hypothesis and is wrong. The magnitude tracks program LAYOUT around 5.5e6, i.e. a static data address rather than a slot offset, so whoever fixes it is looking for a place that yields the ADDRESS of the class's storage instead of reading through it. Verified NOT a value collision: class first, `V = 12345`, pxx answers 12345."
---

## Summary

See the frontmatter. Split from
`bug-n-a-class-reached-through-a-unit-alias-is-not-a-value`, which keeps the
method-call arm.

## Why it is two bugs and not two faces of one

| | this ticket | the other arm |
| --- | --- | --- |
| observable | wrong VALUE, silent, exit 0 | REFUSAL (`AttributeError`) |
| construct | attribute READ | method CALL (`@staticmethod`, `@classmethod`) |
| imports | **dependent** | needs no import, no package, no alias |
| about binding? | needs a differently-named binding | yes, `g = gl; g.s()` |

Only the second is about binding alone. They were filed as one because both
were first seen through a unit alias, which neither of them actually requires.

## What blocks the demo, and it is the OTHER one

frankZ corrected the ranking argument at `201131b40`: lekkerzeilen's seam writes
`gl = _backend.gl`, the **same-name** spelling, which resolves. So the corpus is
hit by the method-call arm, not by this one. **This arm is worse in KIND and the
other arm is what blocks goal 4** — rank them on different things and say which.

## The reproduction condition was wrong in three published statements

Recorded because the way it was wrong is the reusable part, not the condition.

1. frankZ: "a module-level assignment preceding the class". Too narrow on both
   axes.
2. frankuser: **could not reproduce it at all**, on the same binary
   (`c53cb51926a2`), and correctly declined to retire the arm on a miss.
3. frankZ, corrected at `201131b40`: a differently-named binding **and** any
   preceding construct, a docstring included.

**frankuser's miss was not a measurement failure — it was a MINIMISATION
failure**, and the minimised program is the one everybody writes first. See
`devdocs/dev/debugging-playbook.md`, "minimising a repro can delete the
condition".

## First step for whoever takes it

Not a re-reproduction: that is done, three times, by two seats. Find the site
that yields the class's storage ADDRESS where a read-through was meant. The
magnitude tracking program layout rather than field order is the discriminator
that says it is not an index bug.
