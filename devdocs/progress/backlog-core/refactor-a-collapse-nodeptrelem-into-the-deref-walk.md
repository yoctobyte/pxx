---
slug: refactor-a-collapse-nodeptrelem-into-the-deref-walk
title: "`NodePtrElem` has no callers left outside the walk that falls back to it"
track: A
prio: 30
type: refactor
blocked-by: []
status: new
owner: ""
created: 2026-08-30
summary: "After the deref-shape widening, NodePtrElem in pasparser_lval.inc is reached from exactly two places, both inside ResolveDerefShape itself: the final else and the tyUnknown backstop added by bfb7b4c59. Measured with a counter and an arms-disabled control, neither fallback fires on any shape tried, including the compiler's own 436 deref-walk calls -- the new arms take those hits one for one. Not deleted on that: the population is six files, and NodePtrElem's False return is what both fallbacks branch on."
---

# What is left of the two-predicates ticket

[[refactor-a-two-predicates-answer-what-a-caret-yields]] made
`ResolveDerefShape` a superset of `NodePtrElem` in shapes, which removed the
harm — swapping a call site no longer trades depth for spellings. It did **not**
collapse the two functions, which was that ticket's stated end state.

## Why it is smaller than it looks, and why it is still not free

`NodePtrElem` has **no external callers**. `15ec54d7a` moved the last one to
`ResolveDerefShape`. Everything reaching it today is inside the walk:

- its own recursion (INDEX base, BINOP operands),
- `ResolveDerefShape`'s final `else`,
- the `tk = tyUnknown` backstop from `bfb7b4c59`.

So the job is not "check every caller"; it is "decide what those two fallbacks
are for". Two things stop a mechanical delete:

1. **Circularity** — both live calls are inside the function that would become
   the wrapper's body.
2. **The contracts differ where it matters.** `NodePtrElem` returns `False` for
   a node it cannot type and both fallbacks branch on that `False`;
   `ResolveDerefShape` answers `tyInteger` instead. Collapsing has to choose one
   and say which.

## The measurement already taken

Counters on both fallbacks and both new arms, built twice (arms on, arms
disabled). With the arms live, `else` and `backstop` are 0 everywhere tried;
with them off, the same counters fire and take exactly the four hits the arms
now take. Full table in the parent ticket.

**That is not enough to delete on.** The population is six files, `compiler.pas`
reads 0 in both columns (so it is evidence about neither), and "I could not
construct a case" describes a search, not the grammar. Whoever picks this up
should widen the population first — a full-tier run with the counters in, which
is a Track T ask — and only then decide delete vs keep.

# Gate

Track A: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`, plus
`test/test_deref_shape_through_arith_and_nonident_base.pas` and the three cast
/deref tests the parent ticket pins. The failure mode here is a wrong VALUE, not
a red, so a counter-instrumented full-tier A/B is worth more than any local run.
