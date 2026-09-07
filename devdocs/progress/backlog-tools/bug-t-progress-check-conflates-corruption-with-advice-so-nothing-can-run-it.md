---
track: T
prio: 40
type: bug
status: backlog
owner: ""
created: 2026-09-07
found-by: frank-subcoord
tags: [progress, tickets, gate, severity, guards]
blocked-by: []
summary: "`tools/progress.sh check` already EXITS 1 on findings, so it is shaped like a gate -- and it is wired into nothing (no hit in tools/gate.sh, tools/sync.sh or .claude/hooks/). The reason is severity: it emits real CORRUPTION (DUP-SLUG, one ticket present in two folders) through the same channel and the same exit code as pure advice (STALE-PARK, NEAR-DUP, DANGLING-LINK, PROSE-EDGE-NOT-IN-FRONTMATTER, DEAD-COMMIT), and offers no way to select a subset -- `check` takes only --track, --strict and --write. Measured 2026-09-07 at 035a42c74: rc=1 with 24 findings, ALL advisory, ZERO hard. So wiring it into gate.sh quick today would redden every gate in the fleet permanently, which is the cry-wolf failure the owner has already ruled on; and because it cannot be wired in, the one class that is genuine corruption has no automatic detector at all. The fix is a severity split, not a new check."
---

# What is actually broken

`check` is a *reporter* wearing a gate's exit code, and the two populations it
reports are not comparable:

| class | what it means | acting on it |
| --- | --- | --- |
| **DUP-SLUG** | one ticket file exists in **two** folders | corruption — two copies, one board row, `resolve` ambiguous |
| STALE-PARK / -HELD | a park's prose cites a now-closed ticket | read it; the slug matched, not the question |
| NEAR-DUP | two slugs are similar | usually fine |
| DANGLING-LINK | a wiki-link resolves to no ticket | five possible repairs, deleting rarely right |
| PROSE-EDGE-NOT-IN-FRONTMATTER | prose states a block the frontmatter lacks | fix on promotion, not before |
| DEAD-COMMIT | a citation names a sha absent from origin | historical, 350 of them |

Every row but the first needs a human to *read something* before acting. The
first is a fact that is always wrong and always mechanically fixable.

# Measured, so the ratio is not a guess

```
$ tools/progress.sh check ; echo rc=$?
rc=1
   9 STALE-PARK-HELD    3 STALE-PARK    7 NEAR-DUP
   2 PROSE-EDGE-NOT-IN-FRONTMATTER    2 DANGLING-LINK    1 DEAD-COMMIT
   0 DUP-SLUG
$ grep -rn "progress.sh check" tools/gate.sh tools/sync.sh .claude/hooks/*.sh
(nothing)
```

# The fix

Split severity, then wire only the hard half:

- **hard** (DUP-SLUG, plus anything later found to be always-wrong-and-mechanical)
  → distinct exit code, or `check --errors-only`
- **advisory** (everything above) → unchanged output, exit 0 in that mode

Then `gate.sh quick` can run the hard half for the cost of a directory walk, or
Track T's watcher can run it on its ticket paths. **Do not wire the whole
check** — 24 advisory findings would redden every gate in the fleet on the first
run, and *"a gate that cries wolf gets ignored, and then it is not a gate"*.

# Positive control — BOTH directions, and the second is the one that matters

1. Copy a ticket into a second folder in a scratch tree; assert the hard mode
   exits nonzero and names it. (A control that only tests this direction passes
   on a mode that returns nonzero for everything.)
2. **On a tree carrying only advisory findings — i.e. this repo today — assert
   the hard mode exits ZERO.** This is the direction the whole ticket exists
   for, and a hard mode that still fails here is unwireable and has changed
   nothing.

# What this is not

Not a request for new checks; `check` already finds the right things. Not a
claim any current finding is wrong. The defect is that **one channel carrying
two severities collapses to the stricter one**, so the output is unusable by a
machine and therefore is read by nobody — the classic shape where a guard exists,
works, and guards nothing.
