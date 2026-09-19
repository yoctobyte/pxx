---
slug: bug-t-the-watchers-auto-close-copies-a-ticket-into-done-and-leaves-the-original-ranked
title: "The watcher's auto-close writes the closed copy into done/ and leaves the backlog original ranked"
track: T
prio: 45
type: bug
status: backlog
owner: ""
created: 2026-09-19
summary: "MEASURED 2026-09-19 (frankS): 19 open tickets had a same-slug twin in `done/`, and ALL NINETEEN of those twins carry the line `auto-closed by the borg watcher`. One mechanism, no exceptions. The auto-close writes the closed copy into `done/` and does not remove the `backlog/` original, so the duplicate keeps its `prio:` and goes on sorting alongside live work — which is how a seat gets dispatched to a subject that has been passing since 2026-09-16. It also breaks the close path: `progress.sh resolve <slug>` refuses with `ambiguous slug ... matches backlog/... done/...`, so the ONE command that would tidy it up is the command the duplicate disables. Verified every backlog copy is a strict SUBSET of its done twin (19 of 19; the twin is the same file plus the auto-close `## Log` line), so nothing was lost by deleting them — done in this commit. The 19 are removed; THE WATCHER IS UNCHANGED and will re-create them on the next auto-close, which is why this is filed rather than only swept. Found while censusing the 17 open NilPy regressions: 10 of the 17 could not be resolved at all, and the refusal was this. Do NOT rank this on the 19 — a count of duplicates is not a count of work, and the cost is the mis-dispatch, not the disk."
---

# What

`tools/twatch.py`'s auto-close path puts the resolved ticket in
`devdocs/progress/done/` and leaves the original where it was.

Both files then exist with the same slug. The slug is the dedupe key and the
close key — the auto-filed ticket header says so itself — so a duplicate
defeats both.

# How it was found

Not by looking for it. A census of the 17 open NilPy regressions ran each
ticket's own `Repro` line through testmgr's job runner; all 17 came back GREEN
(with a positive control on a job known to be RED, so the runner was not
blind). Closing them, 10 of 17 failed:

    ambiguous slug regression-test-nilpy-test-nilpy-to-bytes — matches:
      devdocs/progress/backlog/regression-test-nilpy-test-nilpy-to-bytes.md
      devdocs/progress/done/regression-test-nilpy-test-nilpy-to-bytes.md

Both copies identical, same `Found:` timestamp, same sha, same failing step.
The `done/` copy had one extra section:

    ## Log
    - 2026-09-16 — auto-closed by the borg watcher: ... passes at 881fdee59b6f
      (tier full); it was red at 5dbee723e228.

# Scope

19 of 608 open tickets, across `regression-*` slugs only — `test-nilpy` (9),
`test-core` (5), `lib-test` (4), and one `regression-cascade`. All 19 done
twins carry the auto-close line; none was closed by hand.

# What this costs, and it is not disk

A duplicate carries a real `prio:`, so it sits in `ready`/`next` beside live
work. That is the mis-dispatch this project already has a rule about: a seat
picks up a ticket whose subject has been green for days. Three of the ones
removed here were p70.

The second cost is that it disables its own remedy — `resolve` refuses an
ambiguous slug, so the duplicate cannot be cleared by the normal path.

# Fix shape

The auto-close should MOVE, not copy. If a copy is deliberate (so the
pre-close state is preserved), the original must at least lose its `prio:` or
gain a terminal status, or `resolve` must learn to prefer the open copy when a
slug is ambiguous and the other match is already terminal.

# Positive control for any fix

Auto-close one ticket and assert that **no file with that slug remains outside
the terminal folders**. Asserting only that the `done/` copy appeared is the
check that passes today.
