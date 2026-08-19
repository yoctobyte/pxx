---
slug: decide-finalize-noop-vs-refusal
track: U
type: decide
prio: 50
status: backlog
blocked-by: []
summary: "`Finalize(x)` is accepted and does nothing — deliberately, as a documented v1 shortcut. FPC empties the string; pxx leaves it intact. Refusing it is separable from implementing it and far cheaper, but would break code that currently compiles. Fork: refuse now, implement now, or leave the silent no-op."
---

# Decide: should `Finalize()` refuse, or keep silently doing nothing?

Routed to Track U by the coordinator; **found and banked by frank2 (Track A)** while
re-measuring `feature-pascal-initialize-finalize-intrinsics` before starting it. It
did the right thing — measured first, found the ticket's premise wrong, and escalated
instead of picking a direction.

## The fact, verified

`Finalize()` is **not missing**. It is parsed, its arguments are consumed, and an
empty sequence is emitted — `compiler/parser.inc:23122`:

```
{ Finalize(x[, n]) — releases a managed value in FPC. pxx manages
  AnsiStrings by scope/assignment (ARC), so v1 parses-and-discards the
  call (no-op). NOTE: a Finalize-reliant container leaks managed
  elements until this maps onto the ARC release helpers. }
```

So `Finalize(s)` leaves the string **intact** where FPC empties it.

**This was a deliberate v1 decision, not an oversight** — which is what makes it a
decision rather than a bug report. The reasoning is sound on its face: pxx manages
AnsiStrings by scope and assignment, so the *common* reason to call `Finalize` does
not apply. The comment also states the cost it accepted: a Finalize-reliant container
leaks managed elements.

## Why it needs you rather than a default

Two of this repo's own rules point in opposite directions here.

- **Refusal beats a wrong value.** A call that silently does nothing is the failure
  shape the dialect work keeps trying to eliminate: FPC-shaped code compiles, runs,
  and quietly does not do what it says. Nothing warns.
- **Reference compatibility is the default.** FPC accepts `Finalize` and gives it
  meaning, so refusing it is a deviation from the reference — normally something
  that lives behind a `--strict-*` flag rather than in the default dialect.

The tie-break is not derivable from the code, and the populations differ: code that
*calls* `Finalize` and code that *depends on* its effect are not the same set.

## The fork

1. **Refuse it** (frank2's read: separable and far cheaper than the feature). A
   compile error where FPC has a meaning — loud, honest, and it converts a silent
   wrong value into a fixable diagnostic. **Cost:** breaks code that compiles today,
   including any in-tree corpus that calls it decoratively without depending on it.
2. **Implement it** — map onto the ARC release helpers so it means what FPC means.
   Fully compatible, no breakage, but it is the whole feature rather than the cheap
   half, and it is what the existing ticket already proposes.
3. **Leave it, but warn.** Middle path not in frank2's framing: keep accepting it,
   emit a warning by default. Nothing breaks, the silence ends, and it converts to
   (1) or (2) later without a flag day. Precedent exists — the bare-funcname read
   warns by default since 2026-08-03.
4. **Leave it silent.** Defensible if no real code depends on the effect, but it
   keeps a documented leak with no signal at the call site.

**Coordinator recommendation: (3) now, (2) when the ARC helpers are convenient.** It
ends the silence immediately, which is the actual harm, without spending the breakage
budget of (1) on a question we have no usage data for. If you want (1), the warning
from (3) is also how you'd measure the blast radius first.

## Notes

- Related, and worth deciding together if you touch this: the existing feature ticket
  `feature-pascal-initialize-finalize-intrinsics` asserts the intrinsics are
  *missing*. **Its premise is now known wrong for the `Finalize` half** and it should
  be corrected whichever way this goes.
- `Initialize()` was not measured. Same question may apply; do not assume it matches.
- Whichever option wins, this stops being a U item and re-files into Track A (or P for
  a dialect-level refusal) as ordinary work.

---

# DECIDED 2026-08-19 by the user — **implement it** (option 2)

> "If a programmer wants to `Shoot.Foot()` it is able to. That is Pascal design in its
> purest. So anyway, yes, Finalize should be implemented. Not sure why this even was a
> question."

## The governing principle, stated plainly

**A Pascal programmer is allowed to shoot their own foot.** The dialect does not refuse a
construct because it *can* be misused — that is the language's design, not a defect in it.
So "this is dangerous if used carelessly" is **not** grounds for refusal; it is grounds for
documentation. Refusal is for things that cannot be given a correct meaning, not for
things that require care.

This settles the tie the ticket could not: "refusal beats a wrong value" applies to a
construct we **cannot** implement correctly. `Finalize` is not that — it has an exact,
implementable meaning. So reference compatibility wins, and the silent no-op (which *is* a
wrong value) goes away by implementation rather than by refusal.

## Why it was a question, and the honest answer

Because it was **priced wrong**. The fork was framed as "cheap refusal versus the whole
feature", and two measurements taken while discussing it dissolved that:

- **In-tree callers of `Finalize`: zero.** The single grep hit is the parser's own
  definition. `Initialize`: zero. So there is no regression risk in implementing it and no
  breakage budget being spent either way — the ticket's own note that this was "a question
  we have no usage data for" no longer holds.
- **The machinery already exists.** `Finalize` is "for each managed field: decrement, nil"
  — the *same* operation pxx already emits at every scope exit, driven by a record layout
  the compiler already knows. The parser comment says as much: *"until this maps onto the
  ARC release helpers."* **The mapping is the work; the helpers are built.**

Third time in two days a ticket's cost estimate did not survive being measured. Same
family as a title naming the encounter rather than the boundary.

## Also decided, and flagged as an EXTENSION of what was asked

`Initialize()` was explicitly not measured by this ticket, which warned against assuming
the same answer. **Implementing it too, on the same reasoning** — and stated here so it can
be reversed if that overreaches:

`Initialize` is the *more* necessary half. Omitting `Finalize` leaks; omitting
`Initialize` makes garbage bytes be read as a refcounted pointer, which is the access
violation. And our own RTL already hits exactly that case —
`lib/rtl/typinfo.pas:315` does `obj := GetMem(sz)` and then **hand-zeroes the instance**
with a comment explaining why, because the intrinsic was not available. Shipping half the
pair would leave that workaround in place.

## Re-filed as work

See `feature-a-implement-initialize-and-finalize-over-the-arc-helpers`. The existing
`feature-pascal-initialize-finalize-intrinsics` has a **wrong premise** (it asserts the
intrinsics are missing; `Finalize` is parsed and discarded) and is superseded by it.
