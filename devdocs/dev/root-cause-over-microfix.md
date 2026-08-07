# Scan for the root issue and the design flaw — do not microfix

**Standing rule, all tracks** (user, 2026-08-07). Sibling of
`normalise-dont-special-case.md` and `ir-as-substrate.md`; those say *where*
generality belongs, this says *when to stop and look up*.

## The rule

A ticket is a **report of a symptom**, not a specification of the fix. Most
tickets here name a plausible cause — and **9 times out of 10 the real fix is
deeper than the ticket says**. So before writing code:

1. **Reproduce, and vary the shape.** One repro tells you it is broken. Three
   neighbouring shapes tell you *what the boundary is* — and the boundary is
   the design flaw. The ticket's own repro is the worst possible sample size.
2. **Ask what the mechanism is, not what the patch is.** Then ask whether the
   mechanism is *right*. A guard that is wrong in one case is usually a guard
   whose soundness argument has a hole, not a guard missing one condition.
3. **Count the mechanisms serving one concept.** Two lowerings for one language
   feature is a smell; three is a design flaw. Build the matrix of
   {lowering} × {access route} and look for holes — the holes are the next five
   tickets, already filed or not yet filed.
4. **Then choose deliberately: microfix or overhaul.** Say which you chose and
   why, in the ticket.

## Why the overhaul is usually *less* work

This is the counter-intuitive half, and it is the reason the rule exists. A
microfix:

- closes one cell of the matrix and leaves the neighbours broken, so it returns
  as a new ticket with a new symptom and a new plausible-but-wrong cause;
- adds a special case, which makes the *next* fix harder and the mechanism count
  go up — the thing that caused the problem;
- is the path by which a subsystem accumulates the four-mechanisms-for-one-idea
  shape that eventually has to be rewritten anyway, but by then with more
  dependents.

The overhaul is paid once, deletes cases rather than adding them, and usually
turns several open tickets green at the same time. **Measure the choice by
tickets-closed-per-change, not by lines touched.**

## The tell that you are microfixing

- The fix is phrased as "also handle the case where…".
- The fix is in the *consumer* of a wrong value rather than where it was made.
- You cannot state the invariant the code now maintains — only the inputs it
  now survives.
- The ticket's own write-up says "small, and covers the common case", and the
  next paragraph admits a second path stays broken. (That admission is the
  design flaw talking. Listen to it.)

## Worked example — NilPy class attributes (2026-08-07)

`bug-nilpy-overridden-class-attribute-read-through-an-instance-gives-the-base-value`
arrived with a confident cause: the instance *read* resolves to the base's slot,
fix by walking from the receiver's class. Measurement said the read is fine and
the *write at construction* never happens. Had that been taken at face value,
the patch would have been in the wrong file entirely.

Varying the shape found the real boundary — and a second, unfiled defect:

| shape | result |
| --- | --- |
| subclass redeclares attr, own `__init__` calls `super()` | silent wrong value (base's) |
| subclass redeclares attr, **no** `__init__` | silent wrong value (base's) |
| subclass redeclares attr, own `__init__`, no `super()` | correct — *by accident* |
| base has no `__init__` at all | correct — different lowering entirely |
| instance read of a class-WRITTEN attribute | **compile error** (separate defect) |

Counting mechanisms: a NilPy class attribute has **three** lowerings
(copy-at-construction field, shared global slot, slot + per-instance override)
and **four** access routes (`C.attr`, bare `attr` in a method, `inst.attr`
statically typed, `inst.attr` on a variant). The matrix is not filled in. Every
bug in the family — four already in `done/`, two open — is one empty cell, and
each was filed as its own "small" bug with its own plausible cause.

The decision `decide-nilpy-class-attribute-instance-read-model` (2026-08-03)
had already chosen the macro answer — follow CPython, real fall-through, "not
phased, not approximated" — and kept copy-at-construction as an *optimization*
justified by:

> divergence requires a class-level write AFTER construction; without one, the
> cheap lowering is provably indistinguishable.

**That soundness claim is false**, and the measurement above is the
counterexample: divergence with no class-level write anywhere. The bug is not in
the guard's conditions, it is in the proof the guard rests on. That is what
step 2 is for, and no amount of care on the reported symptom would have found
it.

## Relation to the other rules

- `normalise-dont-special-case.md` — if a construct is reachable two ways,
  normalise. This doc is the diagnostic that tells you a second path exists.
- **"If you fix a bug on one arm of a double case, grep for the sibling before
  closing the ticket"** is the minimum version of this rule. Building the full
  matrix is the maximum.
- `debugging-playbook.md` — *measure, do not reason*. Root-causing is measuring
  the boundary, not reasoning about the cause. The ticket's stated cause is
  someone else's reasoning, and it is the single most expensive thing to trust.

## What to do when the overhaul is too big for the session

Do not microfix as a consolation. **Bank the diagnosis** — write the measured
boundary, the mechanism count, and the recommended shape into the ticket, and
park it in `unfinished/` (or file the `decide-*` if it is a genuine fork). A
banked root cause is worth more than a patch that has to be reverted, and the
next agent starts from the boundary instead of from the symptom.
