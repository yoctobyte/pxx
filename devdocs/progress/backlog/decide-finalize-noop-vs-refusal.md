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
