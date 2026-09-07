---
track: T
prio: 70
type: bug
status: done
owner: ""
created: 2026-09-07
found-by: frankuser
tags: [twatch, autoticket, autoclose, falsifiability, races]
blocked-by: []
summary: "The watcher auto-closed regression-test-threads-test-threadsafe-class-finalize-race on a full-tier green at 918842a5fd43 -- the same sha the native tier had called RED ten minutes earlier. No tree change separated the two answers, so the green was nondeterminism, not a repair. The job was red again four minutes later and stayed red in both tiers; Track A later found the cause (3bb71fd79, fixed by 35328fd10) and measured it 0/30 before, 30/30 after. None of the three arms of one_green_cannot_close could fire: first stub, class `unit`, no retry in the closing run. Fixed by a fourth arm comparing the closing sha against the red's own sha (762a86705)."
---

# What happened

| when (2026-09-06) | tier | sha | this job |
| --- | --- | --- | --- |
| 12:48Z | full | `12af8ef6` | green (last genuine pass) |
| 12:52Z | native | `918842a5` | **NEW-RED**, segfault |
| 13:02Z | full | `918842a5` | **FIXED** → auto-closed (`e678b743d`) |
| 13:07Z | native | `e678b743` | **NEW-RED** again → refiled as `-2` (`66f56a3d2`) |
| 13:17Z+ | both | … | STILL-RED in every report since |

The green and the red are **the same tree**. The close annotation said so in one
sentence — *"`…race.pas` passes at 918842a5fd43 (tier full); it was red at
918842a5fd43"* — and nothing read it back.

# Why the existing guard did not fire

`one_green_cannot_close()` already had three arms, and this input defeated all
three: the stub was a **first** filing (not a `-2` repeat), the job classes
**`unit`** (not in `RETRY_CLASSES`), and the closing run did not retry (so
`flaky` was unset). The comment above that function is right that
"N consecutive greens" cannot work at any affordable N, and right that the
discriminator has to be free evidence already in the record. Same-sha is such
evidence, and it is stronger than the arms that were there: it needs no
inference about the test at all.

# The cost was a poisoned bisect bound, not the paperwork

A closed ticket reading as "the job is fine" is the obvious harm. The larger one
is that the false green became a **`last good`** bound. The reopen stub `-2`
recorded `bad e678b743d3bb, last good 918842a5fd43, 2 commit(s) in range` — but
`918842a5` had been red ten minutes earlier, and both commits in that range
(`d830416a6`, `d90185cb4`) are tstate/ticket commits touching no buildable file.
So the range could not contain a cause, and it **excluded `3bb71fd79`**, which
is what actually broke it. A wrong close does not only lose a ticket; it aims
the next bisect away from the bug.

# Fix

`762a86705`. Fourth arm in `one_green_cannot_close`, compared at 12 chars so a
full sha matches its own abbreviation either way round; call site passes `sha`
and `r.get("bad")`, which were already in scope. Three guards added to
`tools/twatch_autoclose_race_devtest.py`, two of which assert the rule stays
USEFUL — a later-sha green still closes, and the older no-sha call shape still
closes — because an arm that refuses everything is a silent backlog, not a fix.

# What this does not cover

A green at a **later** sha, on a racy test, still auto-closes on one sample.
That is the reactor case, and the repeat-stub arm only catches it on the second
round trip. Nothing here makes the first close of an intermittent bug safe; it
makes the *same-tree* close impossible, which is the case that carries a
contradiction in its own record.

## Log
- 2026-09-07 — found by frankuser (plexus) from the archive, verified on seven
  against the reports and the ticket pair, fixed by `762a86705` the same day.
  Track A had independently recorded the same-sha reasoning and the bad range on
  `regression-...-finalize-race-2` (`1fc59d487`); this ticket is the mechanism
  half, that one is the defect half.
