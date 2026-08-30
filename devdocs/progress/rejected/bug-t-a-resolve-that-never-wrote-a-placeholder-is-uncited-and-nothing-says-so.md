---
track: T
prio: 45
type: bug
status: rejected
blocked-by: []
found: 2026-08-30
found-by: claude@plexus (Track T face 2), auditing the PENDING-COMMIT residue
summary: "check counts tickets that say PENDING-COMMIT. It has nothing to say about a resolved ticket that cites no commit AT ALL — no placeholder, no sha — which is the strictly worse state, because the placeholder is the thing that announces itself. 3 of 681 tickets resolved 2026-08-16..31 are in it, all resolved by a hand-written Log line rather than `progress.sh resolve`."
---

# A resolve that never wrote a placeholder is uncited, and no instrument says so

## The measurement

`check` currently reports **zero** PENDING-COMMIT — verified two ways
(`check --strict` lists none; `progress.sh pending` prints nothing). The
citation loop is working.

But `check`'s pending scan can only see tickets that **say** `PENDING-COMMIT`.
A ticket resolved by hand — the Log line typed directly instead of through
`progress.sh resolve` — never gets a placeholder, so `sync.sh` has nothing to
fill and `check` has nothing to count. It is uncited and silent.

Scanning `done/` for tickets with a Log entry dated 2026-08-16..31 and no sha
anywhere in the file:

```
3 of 681
  bug-t-the-breadth-banner-vouches-for-cross-targets-on-a-run-that-covers-none
  feature-t-expect-same-a-recipe-assertion-that-prints-its-mismatch
  perf-t-where-the-matrix-actually-spends-its-time
```

All three carry a hand-written Log line (`— fixed with guards; resolved.`,
`— helper landed with guards; resolved.`, `— profiled; findings filed`). None
ever held a placeholder.

**This is the strictly worse state.** `PENDING-COMMIT` is loud: it is a string
that greps, a count that a check reports, and a thing a tool knows how to
repair. A missing Log citation is indistinguishable from a ticket nobody has
finished citing yet, and there is no signal at all.

## Proposed check

`UNCITED-RESOLVE: <slug> is in done/ and cites no commit` for a ticket in a
resolved status whose body carries no sha-bearing citation **and** no
`PENDING-COMMIT`. Two cautions the existing code already learned the hard way:

- **Warning, never repair.** `check`'s own note on bookkeeping citations says it:
  *"Fix by hand with the ticket open — do not bulk-match against git log"*, on
  the recorded evidence that ~82% of bad citations look fixable that way and are
  not. This check reports and stops.
- **Historical tickets must not flood it.** 881 of 2806 `done/` tickets carry no
  citation, nearly all predating the convention. The scan needs a date floor or
  a `--strict`-only gate, or it is 881 findings on day one, which is how a guard
  gets muted — the failure this repo has recorded more than once.

## What was filled, and what was left

- **Filled:** `feature-t-expect-same-...` → `b194ef7ec`. The ticket's title is
  verbatim the commit subject, and an **unbounded** `git log --format=%s
  origin/master | grep -cF` returns exactly **1**.
- **Left for its owner:** `bug-t-the-breadth-banner-...` has **two** exactly-1
  candidates and they mean different things — `62dd38d65` *"fix(T): the breadth
  banner reads the full TIER, not the last replacing run"* (the fix) and
  `0d0230593` *"ticket(T): close the breadth-banner bug; record why the ratio
  ticket stays open"* (the close). Convention says a resolve cites the commit the
  **resolve** landed as, which argues for the close; usefulness argues for the
  fix. That is a convention question, not a lookup — owner `pxx-a5`.
- **Left, unmatchable:** `perf-t-where-the-matrix-actually-spends-its-time`
  resolved as *"profiled; findings filed to the owning lane; two levers measured
  and declined"*. There may be no code commit to cite. Owner `pxx-aa`.

## Why this is filed and not built

The check lives in `tools/progress.py`, which is every lane's tool on every
ticket move rather than Track T's file — the same boundary that sent
`chore-t-board-html-render-is-13s-of-every-ticket-move` to its owner.

Related: `bug-t-sync-fills-one-spelling-of-pending-commit-and-check-counts-two`
(resolved — the placeholder half, which is why the count is 0 today) and
`tools/sync_pending_commit_devtest.py`, whose `prose-mention-is-not-rewritten`
guard already pins the false-positive direction.

---

## Convention ruling, 2026-08-30 (frank-coordinator) — cite the FIX, not the close

The two candidates for `bug-t-the-breadth-banner-...` were `62dd38d65` (the fix)
and `0d0230593` (the ticket move). Ruled: **cite the fix.**

> The "cite the resolve commit" convention exists because that is what `sync.sh`
> can automate at push time, not because the resolve commit is the more useful
> citation. It is an artefact of the mechanism. When a human is filling it by
> hand and the two are distinguishable, cite the thing a future reader needs —
> what changed — and mention the close in the Log line if you want both. A
> citation whose only virtue is that a tool could have produced it is not worth
> preferring over one that answers the question.

Applied: that ticket's Log now cites `62dd38d65` and names `0d0230593` as the
move. Note this does **not** change what `resolve` + `sync.sh` do automatically —
the placeholder path still cites the resolve commit, because that is the only sha
it can know. The ruling governs the hand-filled case, which is this ticket's
whole subject.

**`perf-t-where-the-matrix-actually-spends-its-time` stays uncited.** Its outcome
was *"profiled; findings filed to the owning lane; two levers measured and
declined with reasons"* — a real outcome with no code commit behind it. Forcing a
sha onto it would be fabrication, and an `UNCITED-RESOLVE` check must not treat
this shape as a defect: **some resolutions are not commits.** That is a third
caution for whoever builds it, alongside warn-never-repair and the date floor.

---

## REJECTED 2026-08-30 — measured before building; it cannot be calibrated

I took this to build it and measured the population first. **The check floods at
every date floor, and the number I filed it on was wrong.**

### Correcting my own number first

The ticket says **3 of 681**. That used an ad-hoc test — any line containing
"commit"/"landed as"/"resolved:" *and* a 7–40 hex token counts as cited — which
also passes a ticket discussing a `commit range 8fb3f776..b3fd1c76`. Under the
**house** definition (`CITATION_RE`, plus a line-start `commit|resolved|…: <sha>`
key, which is what `_audit_citations` already uses):

| window (last date in the ticket) | resolved | uncited | |
| --- | ---: | ---: | ---: |
| pre-2026-08 | 1123 | 456 | 41% |
| 2026-08-01..15 | 839 | 161 | 19% |
| 2026-08-16..25 | 481 | 113 | 23% |
| **2026-08-26..31** | **328** | **31** | **9%** |

**31 findings in the freshest six days.** A date floor does not rescue it — the
freshest window *is* the floor, and it still produces 31, of which most cost
nobody anything. That is the `STALE-EDGE-HIDDEN` calibration argument verbatim
(*"17 findings of which 12 cost nobody anything, which is how a check earns the
habit of being scrolled past"*), and it is the failure my own third caution
predicted, arriving through the door of the first.

### The narrower check I went looking for instead, also rejected

A citation whose value is not a sha is strictly worse than none — it *looks*
cited. There is exactly one such form in the tree: **`commit HEAD`, 65 tickets.**

Every one is dated **2026-08-03 or earlier. Zero in the last three weeks.**
The practice stopped on its own. A guard that fires 65 times on history and never
on anything live is a guard that gets muted before it ever catches something —
the same verdict, from the other end.

(The other apparent non-sha values are prose: `commit that`, `commit in`,
`commit range` and friends, 1123 tickets' worth. A check keying on "commit
followed by a non-sha" is a prose detector.)

### The finding that survives, and it is not a check

**Uncited ⟹ hand-resolved, by construction.** `progress.sh resolve` *always*
writes a citation — `PENDING-COMMIT` when no sha is given — and `sync.sh` fills
it. So every ticket in the table above was resolved by typing a Log line
directly instead of running the tool. The uncited population is precisely the
population that bypassed the mechanism.

A check that reports them is treating the symptom. The tool already writes a
placeholder for everyone who goes through it, and the placeholder is exactly the
loud, greppable, repairable marker this ticket wanted. **Nothing is missing from
`check`; what is missing is `resolve` being used.**

That is a habit, not a defect, and it is not worth a warning line that will be
scrolled past. Closing.

### What is left standing from the original filing

- `feature-t-expect-same-...` → `b194ef7ec` and `bug-t-the-breadth-banner-...` →
  `62dd38d65` are filled; both were verified by unbounded exactly-1 subject match.
- The convention ruling above (cite the fix, not the close) stands on its own and
  is the durable part of this ticket.
- `perf-t-where-the-matrix-actually-spends-its-time` stays uncited, correctly.
