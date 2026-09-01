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

## The umbrella instrument — measured 2026-09-01, one day in

The owner asked whether the grouping/umbrella scheme is *measurable*. It is,
with three numbers. All three are one script; recompute them on 09-07.

| | metric | 08-31 | 09-01 |
| --- | --- | --- | --- |
| 1 | **edge coverage** — open tickets with a real `blocked-by` | 42/467 = **9.0%** | 50/561 = **8.9%** |
| 2 | **lift rate** — ranked Track A rows whose position inheritance CHANGES | (n/a) | 4/136 = **3%** |
| 3 | **steered share** — closed tickets that were under an umbrella | (n/a) | 5/42 = **11.9%** |

**Metric 3 against metric 2 is the whole instrument, and it is the one that can
come out false.** Umbrella-lifted rows are 3% of the queue and took 11.9% of the
closed work — roughly **4x over-representation**. If the ranker were decoration,
those two would be equal.

**Why the RATIO and not metric 2 alone:** lift rate is trivially gamed by wiring
every ticket to an umbrella. But wiring everything drives metric 2 toward 100%,
which collapses the ratio to 1. The instrument corrects for its own gaming; a
raw lift rate does not. **Read the ratio, never the lift rate by itself.**

### What it says today

**The mechanism works where it is wired; the wiring is the bottleneck.** Two of
the four lifted rows are exactly the two that got worked last night. But edge
coverage did not move at all — 9.0% to 8.9% — while the open backlog grew
467 -> 561. Umbrellas cannot rank what has no edge, so 97% of Track A still
ranks on a bare `prio:`, which is the number the owner called insufficient.

### Confounds, stated so 09-07 does not read them as signal

- **n = 42 closed, numerator 5.** Small.
- **Part of metric 3 is me, not the ranker.** I pointed frankB at
  `umbrella-managed-memory-is-correct` and asked it to wire its closed children.
  A human pointing at an umbrella is not the ranker steering. On 09-07, prefer
  work nobody was pointed at.
- **One day.** The rules landed 08-31; this is the next morning.

### The falsifier, written down in advance

If on 09-07 **edge coverage is still ~9%**, the umbrella scheme has failed in
practice regardless of what metric 3 says — because it will mean the only edges
are the ones a human asked for by name, and the scheme's claim was that agents
wire them while closing groups. Say that plainly rather than quoting the ratio.
