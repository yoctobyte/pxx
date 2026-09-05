---
track: T
prio: 40
type: bug
status: backlog
blocked-by: []
found: 2026-09-05
found-by: frankuser (incident), frank-coordinator (mechanism, measured)
summary: "/tmp on plexus hit 99% (962M free of 94G); 45G of it was ONE orphaned session scratchpad holding 159,442 files, and deleting it returned the volume to 52%. The reported cause -- 'a benchmark harness that never deletes' -- does NOT reproduce: no committed tool in this repo emits `ab.a.<pid>.bin`/`.map`, so there is no harness to fix and the 'it will refill in about a week' prediction has no mechanism behind it. The actual defect is that a RESTART converts owned scratch into unowned scratch instantly, with no ceiling, no reaper and no owner, and nothing observes the transition -- the 45G was legitimate live scratch until the session that owned it stopped existing. Post-cleanup there are ZERO orphans: all 15.6G remaining was written today by live sessions."
---

# A restart converts owned scratch into unowned scratch, and nothing observes it

- **Type:** bug — Track T (tooling/infra)
- **Status:** backlog, diagnosed not attempted
- **Opened:** 2026-09-05, after the owner cleared the volume by hand

## What actually happened

`/tmp` is a dedicated 94G volume. It reached **99%, 962M free**. `60G` was
`/tmp/claude-1000` session scratch and **45G of that was one directory** —
frankA session `a588203b…`, last written **2026-09-03 14:55**, abandoned by a
restart. Inside, `scratchpad/w` held **159,442 files**: an `ab.a.<pid>.bin` and
a `.map` per A/B iteration. Deleting that one directory took the volume from
**99% to 52%**.

## TWO CORRECTIONS TO THE REPORTED CAUSE, both measured

**1. There is no harness to fix.** The incident report said *"find whichever
benchmark harness emits `ab.a.<pid>.bin`/`.map` pairs and fix it there."*
Measured 2026-09-05 — **no committed file in this repo emits that pattern**:

```
grep -rn 'ab\.\(a\|b\)\b|ab\.a\.' --include='*.sh' --include='*.py' \
     --include='*.mk' --include='Makefile*' .     -> no matches
find /tmp -maxdepth 6 -name 'ab.a.*'              -> 0
```

It was an **ad-hoc inline loop written by a session**, not a tool. So the fix
cannot be "add a `trap ... EXIT` to the harness" — **the harness is the thing
that does not exist**, and the committed `tools/*.sh` already do the right thing,
which is exactly why none of them cause this.

**2. "It will refill in about a week" has no mechanism behind it as stated.** It
refills only if another session writes another ad-hoc loop. Measured after the
cleanup: **there are no orphaned scratchpads of any size.** Every directory over
50M was written **today**, by a live session:

```
4782M  frankB     1890M  frankS      444M  frank-optimize
3808M  frankA     1216M  frankD      253M  frankZ
2547M  frankC      480M  frankH      153M  frank-user (2026-09-04)
                                    total: 15.6G, 22 directories
```

## The real mechanism

**Scratch is reclaimed only by a session ending gracefully, and sessions are
restarted without warning** (CLAUDE.md states this as a standing fact, in the
context of unpushed commits). The 45G was **legitimate live scratch until the
moment its owner stopped existing.** Nothing distinguishes the two states:

- no ceiling — a scratchpad may grow without limit
- no reaper — nothing reclaims one whose session is gone
- **no owner** — and the directory name encodes the CHECKOUT, not the session,
  so `-home-neo-frankA` is reused by every frankA that ever runs; you cannot
  tell a live frankA's scratch from three dead ones sharing the path
- **no observer** — the volume filling was reported by a system alert, nothing
  in this fleet

**This is the `rm`-with-a-variable hazard from the other end.** That rule exists
because deleting is dangerous; the consequence is that harnesses never delete,
never trip a guard, and **nothing errors until the volume does.**

## Options

- **A — a check at session start.** Costs nothing, runs on an event that already
  happens, needs no timer (which this repo refuses). Report `/tmp` usage and any
  scratch directory whose newest file predates today. **Does not delete** — a
  report is safe where a sweep is not, and the deletion stays a human's.
- **B — a ceiling per scratchpad**, reported not enforced.
- **C — nothing; treat it as a once-off.** Defensible: the 45G was one
  pathological loop, and no orphan exists today.

**Recommendation: A.** It is the only one that makes the transition observable,
and observability is the actual gap — the fleet had 48% of a volume in one dead
session's scratch and **not one instrument here noticed**.

## The instrument note, because it belongs to the same family

The incident's own staleness probe was `find <dir> -newermt <today>`, and after
the delete it reported the dead directory as **ACTIVE-TODAY** — because the `rm`
had updated `scratchpad`'s mtime. **The instrument was correct and was answering
about the cleanup, not about the session.** Self-inflicted inside a minute, by
the person measuring. Any check written for option A must read the newest FILE
beneath a directory, never the directory's own mtime.
