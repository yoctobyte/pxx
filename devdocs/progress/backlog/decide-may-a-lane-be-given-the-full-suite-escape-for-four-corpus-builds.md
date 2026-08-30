---
slug: decide-may-a-lane-be-given-the-full-suite-escape-for-four-corpus-builds
track: U
prio: 55
type: decide
status: open
found: 2026-08-30
---

# DECIDE: one yes/no — may a lane run four corpus builds under `PXX_ALLOW_FULL_SUITE=1`?

**This is a single yes/no and it is the entire remaining blocker on an otherwise-landed
ticket.** Raised by frankwasm while triaging parked tickets; routed here rather than
worked around, which was the correct call.

## The fork

`feature-c-import-a-pascal-unit-under-a-mangled-name` is substantially complete. Its §6
needs **four corpus builds** plus one deletion — its own estimate is an afternoon. Those
builds require `PXX_ALLOW_FULL_SUITE=1`, which the `no-full-suite` hook gates and which
**only you can authorise** (CLAUDE.md: "anything else with `PXX_ALLOW_FULL_SUITE=1` in
front of the command, and only when the user asks for it").

The park is right on both counts it makes: the coordinator cannot supply the escape, and
hand-running the recipe bodies to dodge the hook would be **reshaping a denied command**,
which is the thing the platonic-code rule forbids. So nobody proceeded.

## Options

1. **Yes, for this ticket** — name the lane, and it runs the four builds once, reports, and
   the escape does not persist. *(Recommended: smallest grant that unblocks it.)*
2. **Yes, generally, for corpus builds** — a standing carve-out for corpus work, which is a
   bigger change to the hook's meaning than this ticket needs.
3. **No** — the ticket parks on the escape indefinitely and should be re-priced downward to
   stop occupying the ranker, since a blocker only you can clear is not "ready".

## Why it is worth your one word rather than a ticket that waits

There is no derivation available to me here. The hook is permission machinery, it is
yours, and a peer asking for it — or a coordinator reasoning that the ticket deserves it —
is not authorisation. This is the shape Track U exists for: I cannot settle it from the
code, and guessing would be laundering a denied capability through my own judgment.

Also for your attention, unrelated to the above and previously raised without an answer:
**the coordination mandate's `Evaluate: 2026-08-25` passed with no record of evaluation,
renewal or end.** The fleet has been running on it since. One word closes that too.
