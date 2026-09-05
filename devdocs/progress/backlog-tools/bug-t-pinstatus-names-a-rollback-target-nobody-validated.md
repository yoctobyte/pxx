---
slug: bug-t-pinstatus-names-a-rollback-target-nobody-validated
track: T
type: bug
prio: 50
status: backlog
found: 2026-09-05
found-by: frankZ, filed by frank-coordinator
owner: ""
blocked-by: []
summary: "`trackt pinstatus` names v354 as the recovery target and `pin_is_green()` selects it, and v354 cannot compile a SINGLE ONE of the current tree's 54 `lib/rtl` root units. The selection asks whether a pin was green WHEN IT WAS TAKEN -- a true statement about the past -- and prints it where a reader needs to know whether it would work NOW. Nobody validated the target against the current tree, and the tool has the canary's own logic to hand. Fix is small and independent of the design fork (`decide-pair-the-pin-with-the-lib-rtl-it-is-coherent-with`): either run the check and report the real number, or mark the line UNVALIDATED. A tool naming a target nobody validated is worse than a tool naming none, because a named target is acted on and an absent one prompts a question."
---

# `pinstatus` names a rollback target nobody validated

## The measurement

| pin | `lib/rtl` root units it cannot compile (of 54) |
| --- | --- |
| HEAD | 0 |
| v404 (current) | 2 |
| v375 … v403 | 14 |
| v365 | 54 |
| **v354 — the target `pinstatus` names** | **54** |

**Following the advice it prints moves you from 2 broken roots to 54.**

## Why the tool is not lying, which is the reason it went unnoticed

`pin_is_green()` asks **whether a pin was green when it was taken.** That is a
true statement about the past, correctly computed, and recorded at pin time
exactly as the pin grading rules require.

**It is printed where a reader needs a different fact: would this pin work
NOW.** The instrument answered, honestly, about a different question — and the
answer wears the shape of an answer to the one that was asked.

**A green pin from 2026-08-19 is green about the tree of 2026-08-19.** Every
builtin minted since is a cliff it cannot cross.

## The fix, which is small and does not wait on the design call

`pinstatus` has the canary's logic available. Either:

1. **Run it** — compile the `lib/rtl` roots against the candidate and report the
   real number beside the name, or
2. **Mark the line UNVALIDATED** — say that the grade is historical and has not
   been checked against the current tree.

**Either is acceptable and (1) is better. What is not acceptable is the status
quo**, because:

> **A tool naming a target nobody validated is worse than a tool naming none.** A
> named target gets acted on; an absent one prompts a question.

This is the same family as a guard probing a path nothing uses — it passes every
job forever on a healthy box and nothing about it looks wrong.

## Explicitly NOT in scope

**This is not the design question and must not wait on it.**
`decide-pair-the-pin-with-the-lib-rtl-it-is-coherent-with` asks whether a pin
should travel with the `lib/rtl` it is coherent with. **That fork is the owner's
and it is real work. This is a one-line honesty fix to a printed line**, and
splitting them is deliberate so the cheap half can land tonight.

**And neither is a reason to gate a pin.** A valid pin is the self-host
fixedpoint; nothing else may block one. If anything, zero rollback depth argues
for pinning **sooner** — the current pin is the best rollback target that exists.
