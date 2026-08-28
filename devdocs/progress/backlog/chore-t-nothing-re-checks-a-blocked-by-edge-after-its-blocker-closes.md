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

## The query catches HALF the family — three prose instances found later the same day

The fix above is right and should ship. But it reads **frontmatter**, and by the
end of 2026-08-28 three more instances had turned up that no frontmatter query can
see. Whoever implements this should know that a green `check` will not mean the
family is handled.

1. **A stall note that outlived its blocker.** `feature-pascal-corpus-oop` headed
   Track P's queue at **p75** on a 2026-08-20 note whose three clauses had each
   been false for a week: the decision it named was answered 2026-08-21 and sits
   in `decided/`; the ticket it named records itself unblocked 2026-08-22; the
   rung's remaining blocker was in `done/`. Its **frontmatter was clean** — this
   was a paragraph. Corrected in `cc36aeb5a`. Worst shape of it: an umbrella that
   outranks every rung it contains and then tells the reader it has no work.

2. **Prose that INVENTED an edge that never existed.** `feature-pascal-corpus-generics`
   said the edge to `feature-pascal-builtin-tobject-class` was *"recorded as a
   `blocked-by:` edge"*. It never was — frontmatter carried only the typinfo one.
   Found by frankA, `72a21f264`.

   > **Prose can invent an edge as well as outlive one, and the inventing case is
   > worse: it makes the ticket look MORE carefully maintained.** A body asserting
   > that an edge exists reads exactly like a body describing one that does.

3. **A limit that outlived its own refutation, sixty lines above the refutation, in
   the same file.** The same ticket carried *"FPC rejected my override probe, so
   there is no oracle"* — withdrawn later that day (the probe lacked `{$mode}`;
   FPC accepts the override under `{$mode objfpc}{$H+}`), with the correction
   written **below** it. A reader stopping at the first section would act on a
   dead limit. Marked in place rather than rewritten, `a8745196d`.

**Why the prose half is the expensive half.** A stale `blocked-by` is *silent* —
it hides a ticket. Stale prose is *believed* — it reads as prior investigation and
pre-empts the check that would have caught it. Same asymmetry frankA named the
same night: **a false limit is quieter than a false fix and survives longer,
because a wrong fix gets re-tested and a caveat gets believed.**

**What to do about it — not a second query.** There is no reliable scan for "a
paragraph that is no longer true", and building a heuristic that greps bodies for
slug mentions would produce mostly noise and one more instrument whose aperture is
invisible. Two cheaper things:

- **A convention, enforceable by review rather than by tooling:** a body that
  states a blocking relationship must ALSO carry the frontmatter edge, so the
  query above covers it. Instance 2 is exactly the case where prose and
  frontmatter disagreed and only the prose was read.
- **When you close a blocker, the same commit marks the dependents' prose** —
  because *resolving a blocker is an event on the blocker, and the note lives on
  the dependent.* That is why nothing re-reads it: no one is standing there.

Six instances in one day across four sessions, so this is a rate, not a run of bad
luck. Frontmatter is where it is fixable; prose is where it is expensive.
