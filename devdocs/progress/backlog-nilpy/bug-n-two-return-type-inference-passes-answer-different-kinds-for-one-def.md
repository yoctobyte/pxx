---
slug: bug-n-two-return-type-inference-passes-answer-different-kinds-for-one-def
title: two return-type inference passes answer different kinds for one def
track: N
type: bug
prio: 35
owner: unassigned
status: backlog
created: 2026-09-21
found-by: frankH (2026-09-13), re-measured frankb-8e (2026-09-21)
blocked-by: []
summary: >
  A NilPy def is run through return-type inference TWICE and the two passes can
  answer different kinds for the same def, with nothing reconciling them. The
  routine's own comments call two passes disagreeing "a silent ABI mismatch",
  which is the hazard: a caller lowered against one pass and a body emitted
  against the other disagree about how the result comes back, and that is a
  wrong-value or wrong-register bug with no diagnostic. It is NOT firing today —
  the arrangement that would spring it is a def whose two passes disagree AND
  whose caller is lowered between them, and today the second pass wins
  everywhere anyone has looked. Re-measured 2026-09-21 at c63455470: still two
  passes, still disagreeing on `c_rsplit` (tk=22 rec=0, then tk=6 rec=50).
  Rehomed here rather than lost when its parent closed — it was the open
  sub-question inside
  bug-n-a-def-returning-split-on-an-unannotated-receiver-is-typed-a-string,
  which is now in done/ because the defect it was filed for is fixed. Nobody has
  established WHY the two passes differ, and that is the whole ticket.
---

# Two return-type inference passes answer different kinds for one def

## The observation, re-measured at c63455470

    def c_rsplit(label: str):
        return label.rsplit(" ", 1)

    def c_split(label):
        return label.split(",")

`PXXDBG=n.ret` on that file prints **four** lines for **two** defs:

    PXXDBG n.ret def@0  c_rsplit tk=22 rec=0   sawNone=0 trial=0
    PXXDBG n.ret def@21 c_split  tk=6  rec=50  sawNone=0 trial=0
    PXXDBG n.ret def@0  c_rsplit tk=6  rec=50  sawNone=0 trial=0
    PXXDBG n.ret def@21 c_split  tk=6  rec=50  sawNone=0 trial=0

`c_rsplit` is inferred **tk=22** in the first pass and **tk=6 rec=50** in the
second. `c_split` agrees with itself. Both programs run correctly today.

## Why it is filed rather than dropped

Its parent ticket closed on 2026-09-21 because the defect it was filed for —
`c_split` typed AnsiString — is fixed. **This question is not fixed; it was
never diagnosed.** An exculpation needs an owner for the residual, and closing
the parent would have left this in `done/`, where nobody reads it.

## Why it is prio 35 and not higher

Nothing is observably wrong. The second pass wins everywhere anyone has looked,
so the disagreement is currently invisible. It is banked because the failure it
would produce is the expensive kind — a silent ABI mismatch between a caller and
a body, no diagnostic — and because "it works and nobody knows why" is a fact
with a shelf life.

## What would spring it, stated as a mechanism

A def whose two passes disagree, **and** a caller lowered against the first
pass's answer while the body is emitted against the second. Neither half is
exotic. The condition that retires this ticket is either a demonstration that
the two passes cannot disagree for any def a caller can be lowered against, or
a reconciliation that makes the question moot.

**Do not close this by observing that the programs above run correctly.** That
is the state it was filed in.

## First instruments

- `PXXDBG=n.ret` — prints both passes, which is how it is visible at all.
- The routine is `PyInferReturnType` (compiler/pyparser.inc); its own comments
  name the two-pass hazard, so the reasoning is at the site.
- The cheap first question is not "why do they differ" but **"is there any
  ordering in which a caller is lowered between the two passes"** — if not, this
  is a cosmetic double-run and closes cheaply.

## Related

- `bug-n-a-def-returning-split-on-an-unannotated-receiver-is-typed-a-string`
  (done/) — the parent this was the residual of.
