---
slug: decide-the-ticket-lock-is-too-heavy-for-a-per-minute-commit-loop
track: U
prio: 70
status: open
---

# The ticket lock is too heavy for the loop it sits in — 607 commits, 3 locks

**Measured by frankA, 2026-08-30, over the previous six hours of `origin/master`:**

| | |
| --- | --- |
| commits | **607** |
| distinct sessions | **at least 10** (a floor: only 219 of 607 carry a `Claude-Session` trailer) |
| locks in `devdocs/progress/working/` | **3** |

And the three that exist cover an A+S xtensa ticket (correctly), a PAL ticket, and
a Rust ticket. **Essentially the entire night's work ran without a lock.** Checking
the latest commit against every owned file: `ir_codegen.inc` 01:53 (no ticket in
`working/`), `pyparser.inc` 02:09 (none), `cparser.inc` 01:59 (none),
`pasparser_call.inc` 01:08 and `pasparser_generic.inc` 23:33 (none).

## This is not a discipline problem, and treating it as one will not work

frankA's read, which I endorse: **the lock is too heavy for the loop it sits in.**
Agents commit every few minutes; a `claim`/`resolve` round trip per commit is
friction nobody pays voluntarily. The protocol assumes **ticket-granularity** work
and the contention is **file-granularity at commit cadence**. Those are different
shapes, and the gap is where every collision hazard lives.

The near-miss that produced this: `feature-opt-o3-register-pressure` was
*legitimately* released from `working/` when its campaign parked, then the campaign
**resumed without re-claiming** — 8 commits, all in `ir_codegen.inc`. The folder
said `backlog` and was telling the truth about the last deliberate act. So the
ranker offered live work in the hottest shared file to every idle Track A agent,
**correctly by its own rules**. frankA caught it only by opening the ticket at HEAD
before claiming. *A lock is a claim about the present made by an action in the past,
and nothing re-asserts it.* Resuming parked work is the one transition with no
prompt to re-take the lock, because you are continuing rather than starting.

## What I did NOT do

Change the protocol. That is the owner's, and it governs how every lane works.

## What I did do

`tools/whoholds.py` — the *instrument*, not a rule. It answers "who has been
writing to this file and how recently" from commit history, which is current
because it is a side effect of committing rather than something anyone must
remember. It refuses to print a session count as if it were known, and states that
`quiet` means nothing has **landed**, never that nobody is in the file. That
narrows the blast radius; it does not close the question.

## The fork

1. **Keep the lock, add a resume rule** — re-claim on resuming parked work, plus
   an automated nag when a `backlog/` ticket accumulates commits. Cheapest; relies
   on the same voluntary act that is already not happening.
2. **Lock files, not tickets** — a lightweight `claim <path>` with a TTL, matching
   the granularity contention actually has. Closest to the real shape; new
   machinery, and a TTL that expires mid-work is its own hazard.
3. **Drop the lock for hot shared files and rely on `whoholds` + asking** — honest
   about what is already happening; leaves the A/P `lexer.inc` hazard uncovered,
   which is the one the letters exist for.
4. **Make the trailer mandatory and lock nothing more** — does not prevent a
   collision, but makes every one attributable in seconds. Strictly necessary
   under any of the above.

## Recommendation

**4 unconditionally and immediately, then 1.** The trailer gap is not the cause but
it makes every instance unresolvable: frankA could not identify the two agents it
would most have collided with, and I could not tell it who to ask. 219 of 607 is
the number to fix first because it is the cheapest and it makes options 1-3
*measurable* rather than argued.

Then 1, because the failure observed was a **resume**, not a claim anyone skipped —
and a resume rule is one sentence. If collisions persist after both, 2 is the
honest answer and should be built rather than exhorted.

Not 3 while `lexer.inc` is still shared between A and P.
