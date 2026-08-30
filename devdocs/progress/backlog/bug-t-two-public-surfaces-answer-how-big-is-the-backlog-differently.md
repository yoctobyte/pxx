---
track: T
prio: 30
type: bug
status: backlog
owner: unassigned
blocked-by: []
summary: "The published status dashboard says 338 backlog tickets; tools/factsheet.sh says 351. Both defensible -- factsheet counts backlog_new/, the dashboard appears to break those out alongside '20 experimental'. Not a defect in either, but two public surfaces answer the same question with different numbers and the generator's owner should pick one."
---

# Two public surfaces answer "how big is the backlog" differently

- **Type:** bug (reporting consistency) — **Track T** (owns the report format and the
  dashboard generator). Routed by the coordinator, 2026-08-30.
- **Found:** by frankD while resolving `task-d-verify-the-published-status-urls-...`,
  and correctly *reported rather than fixed* — it is not Track D's call and not a
  defect in the docs.

## The divergence

| surface | backlog count |
| --- | ---: |
| published status dashboard | **338** |
| `tools/factsheet.sh` | **351** |

**Both are defensible.** `factsheet.sh` folds `backlog_new/` into the backlog; the
dashboard appears to break those out, alongside a separate "20 experimental". Neither
is wrong on its own terms.

## Why it is worth fixing rather than explaining

The two numbers are published, side by side in the reader's experience, with no
statement of which population each counts. A reader who notices has no way to tell
whether they are seeing a **counting convention** or a **stale generator**, and those
have opposite implications. A reader who does not notice quotes whichever they saw.

**Pick one convention, state it beside the number on both surfaces.** The choice
matters less than the statement.

## The related finding, which is NOT this ticket

frankD's audit of the same figures found that **two of ten published re-measure
commands were themselves wrong**, both undercounting — `ls devdocs/progress/backlog/*.md`
misses `backlog_new/` (338 against 351), and `ls devdocs/progress/decided/*.md` misses a
resolved decision sitting in `done/` (116 against 117). Both are corrected in
`docs/**` already. Note that **the same `backlog_new/` blind spot produced both the wrong
command and this divergence** — so whoever fixes this should check for a third consumer
before closing, per the double-case rule.

See face 184 in [[feature-a-a-refusal-is-a-claim-with-a-date-on-it]]: *a stale number is
wrong once and looks it; a wrong command is wrong on every run, agrees with itself every
time, and therefore reads as verification.*
