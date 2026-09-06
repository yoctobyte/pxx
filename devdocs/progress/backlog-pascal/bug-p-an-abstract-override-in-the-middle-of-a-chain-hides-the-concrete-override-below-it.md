---
slug: bug-p-an-abstract-override-in-the-middle-of-a-chain-hides-the-concrete-override-below-it
track: P
prio: 45
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankS
blocked-by: []
title: "An `override; abstract;` in the MIDDLE of a hierarchy makes the concrete override below it unreachable"
summary: "For A -> B -> C where B redeclares a virtual as `override; abstract;` and C supplies a real body, a call through an A-typed reference to a C instance runs A's body. fpc runs C's. No diagnostic; the program runs and prints a plausible wrong answer. The position is the whole variable and it is sharp: `virtual; abstract;` at the ROOT is CORRECT (pxx and fpc both reach the override), and the identical three-level chain with B's override NON-abstract is also correct — so this is not virtual dispatch in general and not depth, it is specifically an abstract row sitting between a virtual declaration and a concrete override. Pre-existing and unchanged by e8bbdae43/the VMT-propagation fix measured alongside it: the pinned compiler and HEAD print the same wrong answer, which is what identifies it as a second, independent defect rather than a residue of that one."
---

# Measured 2026-09-06, pxx HEAD and pinned agreeing (so: not the VMT-slot fix)

```pascal
{ MIDDLE — WRONG }                        { ROOT — CORRECT }
TA = class procedure Say; virtual; end;   TA = class procedure Say; virtual; abstract; end;
TB = class(TA) procedure Say; override; abstract; end;
TC = class(TB) procedure Say; override; end;   TB = class(TA) procedure Say; override; end;

a := TC.Create; a.Say;                    a := TB.Create; a.Say;
  pxx: A      fpc: C                        pxx: B      fpc: B
```

Third control, isolating `abstract` rather than depth: the same three-level
chain with B's override carrying a real body prints `A B C` under both
compilers, matching fpc exactly. So depth is fine, dispatch is fine, and an
abstract ROOT is fine — only an abstract row *between* the declaration and the
concrete override loses.

## Where to start (not yet confirmed — this is a lead, not a finding)

`FindParentVirtualSlot` (`symtab.inc`) walks ancestors looking for a row with
`UMthVirSlot >= 0`, and its inner `FindUMeth(curr, name)` ALSO walks ancestors.
Both loops start at the same class, so the inner one can answer for a class the
outer one has not stepped to yet. If an abstract row carries `UMthVirSlot = -1`,
the composition is what decides whether the walk resumes at TA or stops — and
the observable says C's `override` ends up with no slot to claim, since A's body
reaches C, which is what an unfilled/inherited slot looks like.

Confirm before fixing by printing `UMthVirSlot` for each of the three rows
rather than reasoning about the loops; the two nested walks are exactly the
shape where a plausible story is available for either answer.

## Why it is worth a slot in the queue

`override; abstract;` mid-hierarchy is ordinary OOP — it is how a base
implementation is deliberately withdrawn from a subtree. The failure is silent
and returns the ancestor's answer, so it is the expensive kind: a plausible
wrong value far from the cause, with no crash to locate it.
