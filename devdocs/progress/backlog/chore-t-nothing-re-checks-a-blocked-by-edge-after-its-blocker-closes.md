---
slug: chore-t-nothing-re-checks-a-blocked-by-edge-after-its-blocker-closes
title: "A blocked-by edge is a claim about the world at filing time, and nothing re-checks it"
track: T
type: chore
prio: 45
status: backlog
found: 2026-08-28
found-by: frankB (second instance in one night), measured repo-wide by frank-coordinator
---

## Measured, not suspected

**14 live tickets carry a `blocked-by` naming a ticket that is now in `done/`, `rejected/` or
`decided/`.** Five were **fully** unblocked — every blocker they name is closed — and all five
were sitting in `blocked/`, which `ready` and `next` **never scan**:

| | ticket | its closed blocker |
| --- | --- | --- |
| N p85 | `bug-n-an-import-alias-binds-to-a-same-named-member-of-the-source-module` | `decide-how-a-compiled-def-carries-its-signature-when-boxed` |
| P p70 | `regression-cascade-4e27dc2be114` | `bug-n-tkinter-is-missing-from-the-python-serving-unit-list` |
| N p60 | `bug-nilpy-songformatter-no-longer-compiles-set-callback-and-get-arity` | `feature-b-tkhtmlview-in-nilpy` |
| N p55 | `bug-n-a-subpackage-directory-does-not-resolve-as-a-module` | `bug-a-a-python-module-s-identity-is-its-name-not-its-file` |
| B p45 | `feature-random-library` | `feature-a-rdrand-cpuid-compiler-builtins` |

Promoted to `backlog/` on 2026-08-28. A **p85** ticket was invisible to the ranker.

## Both polarities, from the same broken edge

This is not one failure mode. It is one stale edge producing two opposite lies, and the second
is the expensive one:

- **Reads BLOCKED, is READY** — the five above. Invisible to `ready`/`next`, so it is never
  dispatched and never ages into anyone's view. Silent.
- **Reads READY, is BLOCKED** — `feature-real-dynlib-loader`: its named blocker resolved, so
  the ranker surfaced it, while **both** remaining items are still blocked by things the
  ticket does not name (no cross loader on this host; the Synapse tree held aside). Found by
  frankB, corrected in `3769f474f`. *A ticket that looks unblocked when it is not is worse
  than one that looks blocked* — it costs a dispatch and an agent's session.

## The fix is a query, not a judgement

`list every live ticket whose blocked-by names a slug in done/ | rejected/ | decided/` is a
one-line scan of the same directories `progress.sh` already walks. Add it to
`tools/progress.sh check` beside the existing "unfinished Track A ticket" failure, so a stale
edge is a **board error** rather than something a human happens to notice twice in one night.

Report both polarities separately — *fully unblocked and still in `blocked/`* is the
actionable one, *partially stale* is a nudge to re-read.

## Why Track T

`progress.sh check` is board infrastructure and T owns the tooling-and-verdicts lane. If T
reads this as A's file instead, re-file it there — the check is the deliverable, not the
letter.

## Related

`feature-a-a-refusal-is-a-claim-with-a-date-on-it` — same shape as **a refusal is a claim with
a date on it**, applied to dependency edges: a `blocked-by` was true when written and nothing
re-dates it. And the same shape as the coordinator's own halt the same day
(`session-roster.md`, 2026-08-28): **a parked flag that nothing can clear is a check that
cannot fail.** Three instances in one day of *state recorded once and never re-derived*.
