---
slug: bug-n-a-field-of-the-same-name-in-an-unrelated-class-defeats-a-property-setter-on-a-bare-receiver
type: bug
track: N
prio: 70
status: open
summary: "SILENT WRONG VALUE: `v.prop = x` on an unannotated receiver silently writes a shadow attribute instead of calling the @property setter, whenever ANY declared class has a plain FIELD of that name — PyVariantPropClass's field-wins precedence loop scans every class and exits on the first hit, so a property on the receiver's real class stops being a property. The getter then reads the shadow back, so the value looks right from outside while the object the setter should have written is untouched."
---

# A same-named field in an unrelated class defeats a property setter

## The condition that springs it

`recv.prop = value` where `recv` has no static class, `recv`'s real class
declares `prop` as a `@property` with a setter, and **some other class —
any class in the program — declares a plain field named `prop`**.

`PyVariantPropClass` begins with a precedence loop over every declared class:
"a real FIELD of that name anywhere wins", exiting on the first class that has
one. That rule is right WITHIN one class (a field beats a dynamic attribute) and
wrong ACROSS unrelated classes, because it never asks whether the receiver could
be the class it found. With the property suppressed, the store falls through to
the dynamic-attribute path, which is STORE ONLY — there is no `PyPropertySet` —
so the setter never runs and the value lands in a shadow attribute.

`pydynattr_get` walks the shadow store BEFORE the declared fields and the
property, so the subsequent read answers from the shadow. **That is what makes
this silent:** the value reads back correctly at the call site while the object
the setter was supposed to write is untouched.

The compiler comment ~15 lines below that loop predicts this failure in its own
words, as the reason the AMBIGUOUS-property case keeps a loud refusal for a
store: *"falling through would turn this loud refusal into the silently-dropped
write ... and the getter would go on answering from the real backing field as
though nothing had happened."* The refusal was placed on one door and this door
was left open beside it.

## Measured 2026-09-20 against CPython 3.14.4

lekkerzeilen blocker 04, `devdocs/pxx-blockers/04-property-setter-skipped-through-bare-receiver/`.

| probe | shape | pxx |
| --- | --- | --- |
| repro | `Boat.throttle` is a property; `Engine.throttle` is a field | `(0.6, 0.0)` vs CPython `(0.6, 0.6)` |
| p2 | **only** `Engine`'s field renamed to `level` | `(0.6, 0.6)` — correct, the setter runs |
| p1 | bare-receiver READ of the property, no store | correct, reaches the getter |
| p3 | neighbouring fields after the bad store | intact — nothing is corrupted, the value goes to a shadow |

p2 is the discriminator: property, receiver and annotation are unchanged and
only the unrelated class's FIELD NAME moves.

## Why the population is large

The shape is property FORWARDING — a class exposing a component's value under
the same name — which is the commonest way the idiom is written. lekkerzeilen is
exactly that: `vessel.py:397` `@property throttle` returning
`self.propulsion.throttle`, against `sim.py:288` `self.throttle = 0.0` in
`Propulsion.__init__`. The demo's boat never moves: accumulated force comes out
`(0.0000, 4704.19, 0.0000)` against CPython's `(1333.01, 4707.28, 792.38)` —
vertical right, both horizontals exactly zero — and the frame still renders.

## Relation to the closed ticket

`done/bug-nilpy-property-setter-is-skipped-on-a-dynamically-typed-receiver` is
the same OBSERVABLE through a different door and its fix is intact: with no
name collision the setter runs. Filed separately rather than reopened, because
the condition is different and the closed ticket's summary is true.

## Family

Same cause family as
`bug-n-a-variant-field-is-claimed-as-the-callee-of-an-open-world-call-with-no-runtime-class-test`
(lekkerzeilen blocker 03): **a same-named member in an unrelated class claims a
dynamic receiver, with no runtime class test.** There it is a field claiming a
method call; here a field claiming a property store. Whoever fixes one should
read the other — the repair is the same, an is-test on the receiver with the
other path as the else arm, and the machinery for those arms already exists
(`PyMakeVariantIsTest`, used by the multi-candidate field and method paths).

A REFUSAL is the acceptable interim if the runtime arm is too big to land at
once: the ambiguous-property store next door already refuses and says "assign to
an annotated local first". A compile error is not a good outcome, but it is a
correct one, and this is a wrong value in a program that renders a clean frame.

## What would retire this

The repro printing `(0.6, 0.6)` unmodified, with `Engine.throttle` still named
`throttle`, and the ambiguous-store refusal next door still firing on its own
case.

## Workarounds for an application — and the rename is NOT one

**Annotating the receiver is the only local fix.** Renaming the colliding field
does NOT work in general, measured by lekkerzeilen-7a on 2026-09-20 after I
recommended it: the precedence loop scans EVERY declared class, so removing one
collision hands the win to the next one. Renaming `Propulsion.throttle` to
`_throttle` left the demo at 0.1 kn with the identical symptom, because
`app.py:514` has `self.throttle = 0.0` in a THIRD class, `Controls`, unrelated
to both the property's class and the component's. Renaming that one too — 13
sites in that class plus 2 `self.controls.throttle` reads — is what made the
boat accelerate.

So the workaround is not "rename the component's field", it is **"rename every
field of that name in every class in the program"**, and that is a property
nobody can hold. For an ordinary noun in a simulator — `throttle`, `current`,
`state`, `value` — a large program is close to guaranteed to have a collision
somewhere, and a NEW collision can be introduced by an unrelated class in an
unrelated module at any time. **A program that compiles and runs correctly today
can be broken by adding a field to a class it never references.** That is the
strongest argument for the runtime fix and against any compile-time
name-precedence patch.

7a's control is worth keeping beside this: the renamed tree run under CPython
gives the same 6.9 kn, so the rename did not change demo semantics and the two
compilers' numbers are being compared on identical source.

## PARKED 2026-09-20 by frankH, deliberately, with the fix specified

Not blocked, not waiting on anyone, and not abandoned — parked because of the
seat's own state, said plainly so nobody has to spend a turn asking.

**What is done.** The diagnosis above, four probes including two negatives, and
a fixture written and failing on exactly the right rows. The fixture lives in
this session's scratchpad and does NOT survive a reboot, so its source is
inline in this ticket; re-deriving it is twenty minutes, not an hour.

**What is next, concretely.** `PyPropertySet` in `compiler/builtin/pylib.pas`,
mirroring `PyPropertyGet` directly above it: find `__prop_set_<name>` in the
instance RTTI, read the value parameter's kind from `TMethInfo.ParamKinds`
(index 1 — index 0 is Self), and call the matching trampoline, returning False
when the kind is not one of the served set exactly as the getter does. Call it
from `pydynattr_set` BEFORE the shadow write, and from nothing else. The
accessor types and `PyPropertyGet` are declared AFTER `pydynattr_set` in that
file, so the setter needs a `forward` declaration rather than moving the type
block. The read path needs no change at all.

**Why parked rather than taken.** This is a change to the runtime attribute
path — it is in every compiled program, and its failure mode is a silent wrong
value, which is the class this ticket is about. The seat holding it had, in the
preceding hour: recommended a workaround that its own diagnosis on the screen
ruled out (the rename, refuted above); backgrounded a gate with `&` inside an
already-backgrounded call and read the wrapper's exit code over the job's, a
trap it had read the rule for the same evening; and censused a population of 91
where the recorded one is 67. All three were caught and none reached a commit,
which is the system working — and three in one stretch is a signal about the
seat, not about the system. A fix here that PASSES and means something slightly
different is the exact profile, and that is not a risk worth taking for a few
hours' earlier landing.

**For whoever takes it, including a later frankH.** Do not start from the
mechanism, start from the fixture: build it, watch it fail on the three rows it
should fail on, and only then write the setter. The row that passes `4.0` to a
clamping setter is the one that separates "the setter ran and wrote elsewhere"
from "the setter never ran" — keep it. And read the workaround section above
before proposing any compile-time repair.
