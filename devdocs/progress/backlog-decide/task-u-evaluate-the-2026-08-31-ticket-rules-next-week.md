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

## Fleet size is a DIAL the owner turns — so do not measure volume

*"Fleet diminished because of tokens. I'm balancing that one"* (owner,
2026-08-31). Agent count is a live token-budget control that will keep moving
week to week. **Every absolute count — tickets filed, commits, notes — moves
with it and measures nothing about the rules.**

**Use per-100-commits rates.** Measured here, and the reason to trust them:

| day | commits | new tickets | **tickets/100c** | logbook lines | **notes/100c** |
| --- | --- | --- | --- | --- | --- |
| 08-26 | 389 | 94 | 24.1 | 0 | 0.0 |
| 08-27 | 431 | 98 | 22.7 | 0 | 0.0 |
| 08-28 | 471 | 76 | 16.1 | 0 | 0.0 |
| 08-29 | 726 | 142 | 19.5 | 0 | 0.0 |
| 08-30 | 1831 | 401 | 21.9 | 61 | 3.3 |
| 08-31 | 638 | *(unmeasurable)* | — | 96 | **15.0** |

**Daily commits swung 4.7x (389 → 1831) while tickets/100c stayed inside
16-24.** That is the property that makes it the right instrument: it is flat
across exactly the variable being tuned. **Baseline: ~21 tickets per 100
commits.**

**The one number that should MOVE is the ratio between the two columns.** Notes
went 0 → 3.3 → 15.0 per 100 commits as the logbook rule landed on 2026-08-30 and
the fix-it-then-note-it rule on 08-31. If the rules work, notes/100c keeps
climbing while tickets/100c falls below 16. If **both** fall, the fleet just got
quieter and the rules did nothing.

**08-31's ticket rate is deliberately marked unmeasurable:** the per-lane split
moved 424 files, and `--diff-filter=A` counts every move as a birth. Next week's
measurement is clean — use earliest-add-per-slug, and `git log --follow` for
anything the split touched.
