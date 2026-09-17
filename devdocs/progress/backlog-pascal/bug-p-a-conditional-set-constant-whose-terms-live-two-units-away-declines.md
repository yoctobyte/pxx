---
slug: bug-p-a-conditional-set-constant-whose-terms-live-two-units-away-declines
title: "`{$if X in S}` declines when S's TERMS live one unit further than S"
track: P
prio: 30
type: bug
status: open
owner: ""
found-by: frankb-56
created: 2026-09-17
tags: [conditional-directives, lexer, fpc-corpus, sets, probe]
blocked-by: []
summary: "The conditional evaluator's probe does not nest -- PasCondProbeUsedUnits refuses at ProbeDepth > 0 -- so a set constant reached through one probe cannot resolve TERMS that need a second. FPC nld.pas:700 asks `cs_opt_use_load_modify_store in supported_optimizerswitches`; the constant is x86_64/cpuinfo.pas:139, its three terms are globtype.pas:428-430, which is two hops. pxx declines LOUDLY (`the right operand of 'in' is not a set constant this pass can read`) and that is the correct direction -- a set missing one member answers `in` with a confident False and takes the other branch. Lifting it is a DESIGN step, not a fix: one save slot becomes a stack, and the ProbeDepth guard that makes the single slot sufficient has to go with it. Banked because it is currently recorded ONLY in paslexer.inc's own comments, where `ready --track P` cannot see it."
---

## The limit is deliberate and its comment says so

`PasCondSetConst` (paslexer.inc):

> probes do not nest (`PasCondProbeUsedUnits` refuses at `ProbeDepth > 0`), so a
> set constant in unit B whose TERMS live in unit C is resolved only when B's own
> lexed range already carries C -- otherwise the nested term declines, the whole
> set declines, and the caller keeps its diagnostic. That is the correct failure
> direction here: a set missing one member answers `in` with a confident False.

So this ticket is not "the decline is wrong". The decline is the safe arm of a
fork where the other arm takes a different branch silently.

## What actually has to change, and why it is not a one-liner

The single save slot is sufficient *because* of the guard, and the file says
that too:

> ONE save slot, not a stack, and that is sufficient rather than lucky:
> `PasCondProbeUsedUnits` refuses to run at `ProbeDepth > 0`, so probes do not
> nest, and the only nesting is probe-inside-expression, which is one deep.
> **A second level would need a stack and would also mean the ProbeDepth guard
> had gone.**

Two coupled pieces, and the second is the interesting one:

1. `SaveCond*` (values, kinds, ints, set masks, ops, names, whys, expr text and
   position, quiet/unresolved flags, err line) plus `SaveCondParent/Active/Taken`
   become indexed by depth rather than singular.
2. **Removing `ProbeDepth > 0` re-opens the re-entry this evaluator has already
   been burned by twice.** A probe calls `LexAppend` on another unit, which runs
   that unit's include expansion and its conditionals; the two measured symptoms
   were `unterminated conditional directive during include expansion` (2026-09-09)
   and FPC's `entfile.pas` -- 175 openers, 175 `{$endif}`, perfectly balanced --
   refused at its last line because a probed unit's directives pushed and popped
   on the OUTER file's `{$if}` stack. A depth-indexed stack must cover the
   `{$if}` nesting state, not only the expression state.

**A bound is required, not optional.** FPC's `uses` graph has cycles, so an
unbounded nesting probe recurses until it runs out of something. Decide the
depth cap and what happens AT it (decline, as today, one level further out) before
building the stack.

## The positive control this needs

The row that must still refuse after the change is the one this ticket's parent
already asserts: an enum with an explicit value in its body, where position stops
meaning ordinal. A probe stack that resolves more must not resolve *that* -- and
`test_p_a_conditional_directive_refuses_a_positional_enum_guess.pas` is the
must-not-compile row that says so.

**And a two-hop fixture must be two hops.** The parent ticket's first three
reductions all came back green because the type was within one hop of the
directive -- the same axis, missed the same way, twice. Vary the DISTANCE, hold
the construct fixed.

## Yield: unknown, and do not rank it on unit count

One corpus unit names this wall (`nld`; `ncnv` moved to `TDoubleRec`). What is
behind it is unmeasured -- nld has advanced through two walls already this week
and found a third each time. Per the umbrella's own rule, a first-failure census
ranks by queue position: clearing this buys whatever nld's NEXT wall allows, which
is not knowable from here.

- **Umbrella:** `umbrella-pxx-compiles-fpc-itself`
- Parent: [[bug-p-a-conditional-directive-cannot-evaluate-in-over-a-set-constant]]
- Sibling wall, same file, different cause: [[bug-p-an-unresolvable-sizeof-walks-every-arm-down-to-an-else-that-raises-fpcs-own-error]]
