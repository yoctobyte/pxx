---
track: T
prio: 30
type: chore
blocked-by: []
summary: "A ticket that is a DESTINATION for findings rather than a task — a standing collector — has no way to say so, so it ranks like work forever. feature-crtl-implement-libc-assumptions said in prose since 2026-07-20 that it has no done state and should not sit in the ready queue; it sat at the head of Track B's queue at p45 for five weeks and was dispatched to an agent as work on 2026-08-28. progress.py reads status and prio, not prose."
---

# A standing collector cannot say so to the ranker, so it ranks like work forever

Filed 2026-08-28 by frankB (Track B) after parking one, on a rule
frank-coordinator stated the same day:

> **A ranked queue says a ticket is UNBLOCKED, not that it has WORK LEFT IN IT.**
> Those are different claims and the board only checks the first.

## Two mechanisms produce a false-ready, and only one of them is a data error

Both fired in Track B on 2026-08-28, on the two tickets at the head of the
queue, which is how they got noticed together.

| ticket | why it ranked | is it a data error? |
| --- | --- | --- |
| `feature-random-library` | a live blocker (`bug-a-xtensa-refuses-to-lower-an-unreachable-syscall`) was never edged onto it | **yes** — fixed in `054ab4ffa` by adding the edge |
| `feature-crtl-implement-libc-assumptions` | nothing blocks it and nothing is wrong with its data; it simply has no work in it, by design | **no** — and that is this ticket |

The first is a mistake anyone can make and the board already models it: the
edge existed in the world and not in the file. The second is not a mistake at
all. The ticket is a **collector** — a place to file the next batch of findings
from a real-project bring-up — and its list is empty exactly when everyone has
been doing their job. Emptying it does not change its rank, so a well-maintained
collector ranks identically to a neglected one.

## What it looks like from the inside

`feature-crtl-implement-libc-assumptions` has said this since 2026-07-20:

> *an ongoing collector by design — its own status line says so — so it does not
> have a "done" state and should not sit in the ready queue as if it did*

It then sat in the ready queue for five weeks, at `prio: 45`, at the head of
Track B, and on 2026-08-28 was dispatched to an agent as work. A second banner
had been added at the top of the file that same morning, in bold, saying the
list was empty. Neither was read by the thing doing the ranking, because
`progress.py` reads `status` and `prio` and nothing else.

**Prose in a ticket is not a signal to a ranker.** That is the same shape as
`bug-t-a-skipped-job-is-passlike-so-it-becomes-a-false-last-good` and as
[[chore-t-a-wikilink-to-a-ticket-that-does-not-exist-is-never-detected]]: a
claim that is legible to a human reader and invisible to the tool that acts on
it.

## Worked around today, not fixed

The collector is now parked in `rainy-day/`, which is loaded but never ranked
(`progress.py`'s `RANKED_STATUSES`). That is the right *behaviour* and the wrong
*name*: `rainy-day/`'s own README describes big work, stretch goals and design
parks, none of which is what a live collector is. A reader who finds it there
will reasonably conclude it was demoted.

`prio: 10` was considered and rejected — CLAUDE.md names that anti-pattern
directly, that parking by priority "keeps it in the ranker's scan forever at
zero value". The choice available today is rankable or parked, with nothing in
between, and a collector is neither.

## Options

1. **A frontmatter field**, e.g. `standing: true` — excluded from
   `ready_tickets()` while keeping `backlog` status, prio, and board presence.
   Says what is true, in the place the tool reads. Smallest change.
2. **A `collector/` folder** alongside `float/` and `experimental/`, added to
   the deliberate-exclusion list in `progress.py`. More visible, more machinery,
   and there may only ever be two or three of these.
3. **A `check` warning** when a ranked ticket has been ready and unclaimed for N
   weeks at a high prio. Catches this case and the missing-edge case and cases
   nobody has thought of — but it is a heuristic, and it would have flagged
   `feature-crtl` in week two rather than answering what to do about it.

Recommendation: **1**, with 3 as a separate ticket if the pattern recurs. The
field is honest, it is one predicate in `ready_tickets()`, and it makes the
ticket's own five-week-old sentence enforceable instead of decorative.

## Gate

Track T tooling change, so T's own gate applies (the quick tier, per CLAUDE.md's
per-fix loop — not a wider one), plus a devtest beside
`progress_ranked_statuses_devtest.py` asserting a standing ticket is loaded,
satisfies blockers, appears on the board, and does NOT appear in `ready`/`next`
for its own track.

## Scope note

T owns the tool. Whichever option is taken, `feature-crtl-implement-libc-assumptions`
moves back out of `rainy-day/` and into whatever the answer is — it is a Track B
ticket and its content is unaffected.

## Second instance, and it widens the field beyond collectors (coordinator, 2026-08-28)

`feature-b-posix-and-fpc-named-socket-facades` [B p25] is a better instance than
the crtl collector, and it is a **different kind**. Its own second line reads
*"filed to preserve a design, not to schedule work"* — it says outright that it
is not work — and it sits at p25 rather than at a queue head, so it misleads
**less** than the collector did. It still got offered as work, twice: once by the
ranker, once by me.

That matters for the field's scope. The collector case invites reading `standing:`
as *"this ticket is a standing survey"*. This case is a **preserved design**:
nothing to survey, nothing recurring, no consumer — just a record someone will
want if and only if they open that work. Both belong out of the ranked queue for
the same reason, and it is not "it recurs". It is:

> **the ticket's value is not conditioned on anyone acting on it now.**

Two shapes so far — a standing survey and a preserved design — which is why the
field should NOT be named for either. `standing: true` reads as the first one.
Something closer to `ranked: false` says what it does rather than why, and admits
the third shape nobody has hit yet.

**A caution the first instance did not surface.** This one was *inaccurate at the
moment it was filed* — written from `feature-networking`'s design log rather than
from the tree, so it claimed the FPC-named facades were never built when
`sockets.pas` (633 lines, 4 consumers) and `baseunix.pas` (149 lines, 10 files
naming it in a `uses` clause) are built and load-bearing. Corrected same-day by
its own filer (`f2d76bc30`). Unranking a ticket makes it **less likely to be
re-read**, so whatever the field is called, an unranked ticket's claims decay
with nothing pushing back — the crtl collector's premise and this one's were both
wrong within days of filing. That is an argument for the field, not against it,
but it is also an argument that unranking should not be silent: it wants a date.
