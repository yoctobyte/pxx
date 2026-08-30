---
track: U
prio: 55
type: decide
status: backlog
owner: unassigned
blocked-by: []
summary: "The O charter names -Os, -Ofast and -funroll-loops as the shape a trade-off takes -- an author chooses WHICH trade, not HOW MUCH -- but NONE OF THE THREE EXISTS. No named trade-off flag has ever been built, so the axis is described and empty. A first candidate now exists: the x86-64 static-literal retain guard, measured -3.96% on literal-heavy code and +6.95% on the real workload (compiler.pas), i.e. a genuine trade rather than a win or a loss. The fork: do we open the named-flag axis at all, and what is the bar for putting a pass behind one -- given that PROMISE (delivered value, measured) and PROOF (Track T full tier) were ruled for the -O levels and a trade-off flag by construction cannot show net promise? Filed by the coordinator at frank-optimize's request; frank-optimize declined to file it while holding the candidate."
---

# Decide: do we introduce the named trade-off flag axis, and what is the bar?

- **Type:** decision (Track U) — filed by the coordinator, 2026-08-30.
  **frank-optimize deliberately did not file this**, on the grounds that it holds
  a candidate and would be filing its own change's home. That is the right call
  and is why the ticket exists with no author's pass attached.

## The gap

`decided/decide-the-o-level-charter` rules that trade-offs are **not a level**:

> *"Bigger code / worse float / longer compiles" is a different axis and stays a
> named flag: an author chooses WHICH trade, not HOW MUCH (`-Ofast`, `-Os`,
> `-funroll-loops` are sideways, not "more than `-O3`"). A mature pass that is
> merely not universally beneficial is a flag.*

**None of those three flags exists.** The axis is fully described and entirely
empty, so "make it a flag" has never actually been available as an outcome — it
has been a way of saying "not a level".

## Why it is live now

frank-optimize's x86-64 static-literal retain guard, measured:

```
4 literal stores only   (max saving)    -3.96%
mixed                   (realistic)     -3.04%   [unreliable, see below]
4 managed, zero literal (pure cost)     +3.66%
compiler.pas            (real workload) +6.95%
```

A load+cmp+branch on every managed retain costs more than the store it saves on
the literal subset. **That is a trade, not a defect**: it is a win on
literal-heavy code and a loss on retain-heavy code, and which one you are is a
property of the program. The aarch64 half is an unconditional win and landed
separately.

## The fork

1. **Open the axis** — build the flag machinery and land this behind it. Cost:
   a new user-visible surface, a combinatorial testing question (`optdiff`
   currently sweeps levels, not flags), and every future "not universally
   beneficial" pass now has somewhere to go, which may be a feature or a
   backlog magnet.
2. **Leave the axis empty** — a pass that is not universally beneficial is not
   shipped. Cost: the charter keeps describing a mechanism nobody can use, and
   measured work with a real constituency is discarded.
3. **Defer until there are N candidates.** One data point is a poor basis for a
   user-visible axis; the machinery is the same whether it holds one flag or
   five, and the bar is easier to set against a set.

## The part that needs ruling either way

**PROMISE and PROOF were ruled for `-O` levels** (`2a8c56fd1`): delivered value,
measured, plus Track T's full tier. **A trade-off flag cannot show net promise by
construction** — if it could, it would be a level. So if the axis opens, it needs
its own bar, and the obvious candidate is *"promise on a NAMED population, proof
unchanged"*. Nobody has ruled that.

**Not in scope:** whether frank-optimize's pass is good. Its numbers, retractions
and regeneration recipe are in its own ticket.
