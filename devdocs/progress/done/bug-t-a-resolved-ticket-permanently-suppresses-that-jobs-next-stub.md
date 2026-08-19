---
track: T
prio: 60
type: bug
blocked-by: []
commit: PENDING-COMMIT
claimed-by: plexus-T
summary: "`already_filed` scans every bucket including `done/` and `rejected/`, so once a job's regression ticket is RESOLVED that job can never auto-file a stub again — silently, because the filing loop just `continue`s and prints nothing. 182 resolved `regression-*` slugs on this repo are in that state. Caught when `lib-test#src:test/lib_tls.pas` went NEW-RED and no stub appeared, its predecessor having closed with the words 'reopening is by a fresh NEW-RED stub'."
status: done
---

# A resolved ticket permanently suppresses that job's next stub

Filed and fixed 2026-08-19 by Track T (plexus-T), from a coordinator's
observation that the `6070883b46e7` NEW-RED had no stub in `backlog/`.

## The defect

`already_filed(pdir, slug)` walks `PROGRESS_BUCKETS`, which is every bucket —
`urgent, working, unfinished, backlog, blocked, done, rejected`. `file_stub_tickets`
then does:

```python
slug = reg_slug(job)
if already_filed(pdir, slug):
    continue
```

So a ticket in `done/` suppresses filing exactly as hard as one in `backlog/`.
The intent behind the broad scan is real and worth keeping — one job must never
hold two live tickets, and a renumbering must not file a duplicate. What it does
not distinguish is **why** a ticket exists:

| bucket | what it means | should it suppress? |
| --- | --- | --- |
| `urgent`/`working`/`unfinished`/`backlog`/`blocked` | the work is still owed | **yes** |
| `done`/`rejected` | a PREVIOUS red was already answered | **no** — this is a new finding |

Consequence: **a job becomes unticketable forever the moment its first
regression ticket resolves.** Counted on this repo today — **182** resolved
`regression-*` slugs against **0** open ones. Every one of those 182 jobs is
silently unable to file.

Silently is the operative word. The two visible outcomes both print — `auto-filed
N stub ticket(s)`, or `NOT filing a regression ticket — <reason>`. This path is
neither: the loop `continue`s and the pass ends with `filed` empty, so nothing is
printed at all. The 07:15 run's log goes straight from the RED report to the next
cycle. A reader cannot tell suppression from "the feature is off".

The same reasoning was already worked out ONE FUNCTION AWAY and not carried
across. `stub_sources()` restricts its scan to open buckets, with the comment:

> A ticket in done/ or rejected/ is a finished argument, and a source going red
> again after it closed is a NEW finding that must get its own stub —
> `already_filed` scans every bucket on purpose (same job, same slug, never two
> tickets), but that reasoning does not carry over to [the source dedupe].

The parenthesis is the bug, stated confidently, in the fix for its sibling.

## Why it took a human noticing

`regression-lib-test-lib-tls` closed 2026-08-16 with, in as many words,
*"reopening is by a fresh NEW-RED stub, since a second red is a second finding
with its own range."* That is the behaviour the tool was believed to have. It has
never had it: the very act of closing that ticket is what disabled it.

## The fix

The tension the broad scan was resolving is slug uniqueness — refiling at
`backlog/<slug>.md` while `done/<slug>.md` exists puts two tickets under one
slug. So the recurrence gets its **own** slug:

- `stub_slug_for_filing(pdir, base)` — suppress on an OPEN ticket for any
  variant; otherwise return the first free variant (`<base>`, `<base>-2`,
  `<base>-3`, ...). Refiling after a resolved ticket **announces itself**.
- `live_stub_slug(pdir, base)` — the mirror, so `close_stub_tickets` can find
  what filing opened. Closing looked up the bare slug in `backlog/`, which after
  a refile is the resolved predecessor's name and matches nothing.
- `ticket_bucket()` / `OPEN_BUCKETS` extracted; `stub_sources` now uses the
  constant instead of repeating the tuple.
- `STUB_VARIANT_MAX = 20` runaway guard, which prints rather than going quiet.
- `already_filed` is left as-is and still used by `file_cascade_ticket`, where
  the slug is keyed on the bad sha and "same sha, same event, never twice" is
  the correct rule.

`rejected/` refiles too, deliberately: the previous instance was rejected on its
own evidence, and the refile is bounded — the new `-2` stub then sits in an open
bucket and suppresses everything after it.

## Gate

- `python3 tools/twatch_refile_stub_devtest.py` — new; open-bucket suppression
  for all five buckets, refile-on-resolved for both resolved buckets, variant
  walking, the already-open recurrence, zero-byte debris, the runaway guard, and
  the close-side lookup.
- `python3 tools/devtest_stub_lifecycle.py` — the end-to-end lifecycle, green
  before and after.

## Not fixed here: the 182 already suppressed

The fix is forward-looking. A job whose ticket resolved before today files its
`-2` on its NEXT red, which is the right moment — filing 182 stubs now would be
a cascade of tickets for jobs that are green. Nothing to do, recorded so the
number is not rediscovered.

Found alongside: [[chore-t-five-tool-devtests-are-broken-on-master-and-nothing-runs-them]].
The red that exposed it: [[bug-b-lib-tls-hangs-forever-when-its-hardcoded-port-is-unavailable]].

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.
