---
slug: decide-may-a-lane-be-given-the-full-suite-escape-for-four-corpus-builds
track: U
prio: 55
type: decide
status: open
found: 2026-08-30
status: decided
summary: "RESOLVED 2026-08-31 as a MISUNDERSTANDING OF INTENT -- and the misunderstanding was CLAUDE.md's, not the agent's. Answer: YES, and no permission was ever needed. PXX_ALLOW_FULL_SUITE=1 is a SPEED GUARDRAIL, not a permission gate; the owner: 'those 10 minutes were exactly the issue, because sometimes agents run that full 10 minute test for every byte they edit, which is wasteful... but agents should be able to override it autonomously.' The doc said otherwise in two places and contradicted its own reversibility test three paragraphs earlier -- running tests is reversible, unlike sudo/hardware/money which it was listed beside. CLAUDE.md and the hook refusal text were both corrected in the same commit, because closing this ticket without that fixes one instance of a rule that would keep firing. Unblocks feature-c-import-a-pascal-unit-under-a-mangled-name section 6 (four corpus builds + one deletion, an afternoon). frankwasm was RIGHT to park rather than reshape a denied command."
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

---

# RESOLVED 2026-08-31 — yes, and it never needed asking

Owner: *"i'm not sure why we recorded that only the human can grant it... agents
should be able to override it autonomously."*

## The misunderstanding was the DOC's, not the agent's

frankwasm followed CLAUDE.md exactly. It said, twice:

> Track T escapes with `PXX_TRACK=T`; anything else with
> `PXX_ALLOW_FULL_SUITE=1` in front of the command, **and only when the user asks
> for it.**

> 3. **Authority only he holds** — `PXX_ALLOW_FULL_SUITE=1`, sudo, hardware, money.

Parking rather than reshaping a denied command was the correct response *to those
words*. The defect is that the words were wrong.

## And the doc contradicted itself, three paragraphs apart

> **The test is REVERSIBILITY, not importance.** Reversible → do it and report.

Running a full suite is entirely reversible — ten minutes of CPU, no one-way
door, nothing leaving the machine. Listing it beside **sudo, hardware and money**
miscategorised a *speed guardrail* as a *permission boundary*.

## What it was actually for

Owner: *"those 10 minutes were exactly the issue, because sometimes agents run
that full 10 minute test for every byte they edit, which is wasteful."* The
target was the reflex, not the capability.

## Fixed at the source, not just here

Both sites in `CLAUDE.md` and the hook's own refusal text now say: autonomous, no
permission needed, a speed guardrail — **run it when you genuinely need it, and
say in the commit why the quick tier was not enough.** Hook *behaviour* is
unchanged; only its message.

Closing this ticket alone would have fixed one instance of a rule that would keep
firing, on the next agent that read the same two lines.

## Unblocks

[[feature-c-import-a-pascal-unit-under-a-mangled-name]] §6 — four corpus builds
plus one deletion, its own estimate an afternoon. No grant required; just run it.

## Still open, and it is not this ticket's

The coordination mandate's `Evaluate: 2026-08-25` passed with no record of
evaluation, renewal or end. Raised here twice now without an answer. It needs one
word from the owner: renew, end, or set a new date.
