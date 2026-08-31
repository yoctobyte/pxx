---
slug: task-u-evaluate-the-2026-08-31-ticket-rules-next-week
title: "Evaluate the 2026-08-31 ticket rules — on or after 2026-09-07"
track: U
prio: 60
type: task
blocked-by: []
created: 2026-08-31
summary: "Owner asked to evaluate the new rules next week. Written as a ticket rather than a scheduled callback BECAUSE timed callbacks are one of the rules. Carries the 2026-08-31 baseline so the comparison is possible at all -- without it, next week's evaluation is an opinion."
---

# Evaluate the new rules, on or after 2026-09-07

Owner, 2026-08-31: *"let's evaluate our new rules next week."*

**Not a cron and not a `/loop`** — a timed callback is exactly what the new rules
ban. This ticket is the memory instead, which is one of the three legitimate
reasons to file anything.

## The baseline — measured 2026-08-31, method stated so it can be repeated

| | value | how |
| --- | --- | --- |
| open tickets | **467** | `backlog-*`, `urgent`, `working`, `unfinished`, `blocked` |
| distinct tickets ever filed | **5035** | earliest add per slug, `--until` today |
| new tickets/day, late Aug | **70-128** | same, per day; **365** on 2026-08-30 |
| open tickets with a real `blocked-by` | **42 (9%)** | `grep -h '^blocked-by:' | grep -vc '\[\]'` |
| `done/` | **2958** | |
| `bugnotes.md` entries | **0** | file created today |
| umbrellas | **5** | `backlog-umbrella/` |

**Do NOT measure edges with `grep -L 'blocked-by: \[\]'`.** That answers *"files
not containing this literal string"* and counts a ticket with no such field as
though it had an edge. It produced a wrong number in this very session, which
then reached CLAUDE.md and had to be corrected.

## The questions, and what would answer each

1. **Did the inflow drop?** New tickets/day vs 70-128. *But read it with the
   agent count* — 2026-08-30's 365 was an eleven-agent night and the fleet now
   runs 2-3. A drop caused by fewer agents is not the rules working.
2. **Did fixing replace filing?** `LOGBOOK.md` lines and `bugnotes.md`
   paragraphs per day vs new tickets per day. The rule intends the first two to
   rise as the third falls. **If all three fell, the rules did not work — the
   fleet just got quieter.**
3. **Did the umbrellas grow edges by ATTEMPT?** Edge count vs 42, and whether
   new edges name failures from a real compile attempt rather than a backlog
   sweep. An umbrella that grew by triage is the thing the rule forbids.
4. **Did anything break?** Did "fix it on the fly" produce a regression, a
   workaround around a compiler bug, or a delete of code merely *believed* dead?
   Those are the three guards; a single breach is worth more than any count.
5. **Is the per-lane split actually read?** Does anyone use `ready --track X`,
   or did agents keep pulling the global head?

## The honest failure mode to watch for

**These rules could look successful while doing nothing**, because the fleet
shrank from eleven to three the same day. Every count that measures *volume*
falls for that reason alone. Prefer ratios — fixes per finding, notes per
ticket — over totals.
