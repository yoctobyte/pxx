---
slug: grant-progress-py-to-pxx-a5-for-the-uncited-resolve-check
track: T
prio: 45
status: done
---

# GRANT: `tools/progress.py` → pxx-a5, scoped to the `UNCITED-RESOLVE` check

**Granted 2026-08-30.** `tools/progress.py` is every lane's tool on every ticket
move, which is why pxx-a5 correctly declined to edit it unasked and filed
`bug-t-a-resolve-that-never-wrote-a-placeholder-is-uncited-and-nothing-says-so`
[T p45] instead. The coordinator holds it and is the bottleneck; the design is
pxx-a5's, complete, with three cautions it derived itself. Granting rather than
re-implementing from a description.

**Scope:** the `UNCITED-RESOLVE` check inside `check()`, and its devtest. Nothing
else in the file. The coordinator is not editing `progress.py` while this is open.

## The defect

A ticket resolved by a **hand-written Log line** never gets a `PENDING-COMMIT`
placeholder — so `sync.sh` has nothing to fill and `check` has nothing to count. It
is uncited and **silent**, which is strictly worse than `PENDING-COMMIT`, a state
that at least greps, counts, and has a tool that knows how to repair it. Measured:
**3 of 681** in the 2026-08-16..31 window.

## The three cautions, all pxx-a5's, all load-bearing

1. **Warn, never repair.** `check`'s own bookkeeping note records that ~82% of bad
   citations *look* fixable by git-log matching and are not.
2. **A date floor.** 881 of 2806 `done/` tickets predate the convention and would
   flood it with 881 findings on day one — which is how a guard gets muted (129,
   and `STALE-EDGE-HIDDEN`'s calibration comment).
3. **Some resolutions are not commits.** *"Profiled; findings filed; two levers
   measured and declined"* is a real outcome, and **a check that flags it teaches
   people that uncited means nothing.**

Three distinct routes to the same worthless-check failure, which is why this is a
grant and not a ticket description.

## Convention it must encode

Ruled 2026-08-30: **for a HAND-FILLED citation, cite the FIX, not the close.** The
"cite the resolve commit" convention exists because that is what `sync.sh` can
automate at push time, not because the resolve commit is more useful. When a human
fills it and the two are distinguishable, cite what a future reader needs — what
changed — and name the close in the Log line. **The automated `resolve` +
`sync.sh` path is unchanged**; a placeholder can only ever know the resolve sha.

---

## RETURNED 2026-08-30 — unused, and the check landed somewhere else

**`tools/progress.py` was not edited.** The grant is returned unspent; the
coordinator may reopen the file immediately.

### The grant rested on a number I had already retracted

It cites *"3 of 681"* and the ticket as filed. Both were superseded on the same
day, in `72538cc79`, which closed
`bug-t-a-resolve-that-never-wrote-a-placeholder-is-uncited-and-nothing-says-so`
as **`rejected/`**. The 3-of-681 used an ad-hoc test that counts a ticket
discussing a `commit range 8fb3f776..b3fd1c76` as cited. Under the house
definition (`CITATION_RE` plus a line-start key — what `_audit_citations`
already uses):

| window | resolved | uncited | |
| --- | ---: | ---: | ---: |
| pre-2026-08 | 1123 | 456 | 41% |
| 2026-08-26..31 (freshest six days) | 328 | **31** | **9%** |

**The freshest window *is* the date floor**, and it still yields 31. Caution 2
does not survive contact with the data — as a standing `check` report this is the
muted guard its own cautions were written to prevent.

### What changed: the scope, not the check

The same 31 findings are worthless as a standing report over the tree and
valuable **one at a time, addressed to the person who just resolved the ticket,
at the moment fixing it costs one line.** So it belongs beside
`verify_citations_landed` in `tools/sync.sh` — scoped to what this run resolved —
not in `check()` scoped to the tree.

That also dissolves caution 2 entirely: there is no date floor to choose, because
"this push" is the floor.

`manifest_resolved` is captured beside the subject manifest —
`--diff-filter=A --no-renames` over the resolved buckets. `--no-renames` is
load-bearing: a `git mv backlog/ → done/` is reported as **R**, and
`--diff-filter=A` would never see the very move this is about.

### Calibrated against the live board, as asked

Over the last 400 commits touching a resolved bucket: **469 resolutions, 43 would
nudge (9%)**. But 23 of the 43 are `regression-`, `decide-` and `grant-` slugs
whose resolution **is** a verdict rather than a commit — the watcher files and
closes regression tickets from tstate; a decision closes when the user rules; a
grant closes when it is returned, as this one is. Nudging those teaches that
uncited means nothing, which is **caution 3 in live data**.

Excluded by prefix: **19 of 469 — 4%**, about one nudge per twenty-five
resolutions, and every survivor is a `bug-`/`feature-` ticket that changed code
and cited nothing.

All three cautions are honoured, and two of them by construction rather than by
care: **warn, never repair** (it prints, exit 0 — the push already succeeded);
**the date floor** (there is none to get wrong); **some resolutions are not
commits** (the prefix exclusion, plus the message's closing line saying so in
words the reader sees).

### Convention encoded

The message says *"cite the FIX, not the close, and name the close beside it"* —
the ruling, in the place a person is standing when it applies.

### Guard

`tools/sync_citation_guard_devtest.py` — **36 guards, 0 FAIL**, up from 24.
Section 8 covers the nudge and the three excluded prefixes; section 9 is the
scope guard that stops it firing when a *resolved* ticket is merely edited, which
is what every write-up appended to old work would otherwise do.

One more caught by running rather than reading: the function's early-out was
still keyed on `manifest_tickets` alone, making the nudge unreachable whenever
that list was empty. Harmless live — `manifest_resolved` is a subset — but
**accidentally correct is not correct**, and the devtest passes the two
separately, so it failed on the first run.

## Log
- 2026-08-30 — resolved, commit c1a8e092c.

### Folded from a duplicate copy that was sitting in `backlog/`

`check`'s DUPLICATE-SLUG scan caught this ticket existing in `backlog/` **and**
`done/` — the backlog copy was a headless fragment (no frontmatter, so
NO-FRONTMATTER flagged it too) holding my closing note. Diffed before removing, per
the scan's own instruction; the `done/` write-up above is strictly the fuller one.
The single framing worth keeping from the fragment:

> 23 of the 43 are `regression-`/`decide-`/`grant-` slugs whose resolution **is** a
> verdict — that is **caution 3, in live data, at 53% of findings.**

Naming the fraction is what makes caution 3 an argument rather than a worry. Noted
also that my own coordinator check flagged my own duplicate within an hour of my
filing it, which is the check working on its author.
