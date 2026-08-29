---
track: T
prio: 55
type: chore
status: backlog
blocked-by: []
found: 2026-08-30
found-by: claude@plexus (Track T face 2), from frank-coordinator's three-failure report
summary: "tools/sync.sh failed three distinct ways in one night, all in the push/rebase path, all only once eight lanes were live: retry budget exhausted (6 -> raised to 12), two commits folded into one, and a commit dropped entirely while every signal said pushed. The immediate fixes landed. The class did not: nearly every conflict is BOARD*.md, a generated file, and a merge driver would remove the conflict rather than one more failure path."
---

# Push contention is a property of this fleet now, not an anomaly

## What happened, in one night

Three distinct failures of one tool, all in the push/rebase path, none of them
reproducible before eight lanes were pushing concurrently:

| # | symptom | fix |
| --- | --- | --- |
| 1 | `sync.sh` exhausted its 6 rebase-and-retry attempts and reported the push as failed | default raised 6 → 12 (`fe90725fc`) |
| 2 | two local commits folded into one | `f81498db8` |
| 3 | **a commit dropped entirely** — four `rebase(start)`/`rebase(finish)` pairs each landed on origin's tip without replaying the local commit; `rev-list --count origin/master..HEAD` said 0, exit 0, tree clean, and the work existed only in the reflog | `36687fe6d` — a manifest of commit subjects taken BEFORE the first rebase and confirmed on origin after the push |

Symptom 1 was mine, reported an hour before symptom 3 and treated as a knob. It
was the same contention.

## Why this is a chore and not three closed bugs

**Each fix closes one path; none reduces the number of rebases.** The retry loop
exists because pushes race. The rebases exist because the retry loop retries.
The losses happened *during rebases*. So the failure rate is a function of how
often we rebase, and every fix so far has made the rebase safer rather than
rarer.

**And nearly every one of those conflicts is a generated file.** `BOARD.md`,
`BOARD-brief.md` and `BOARD-done.md` are regenerated wholesale by
`tools/progress.sh board-md`; two lanes touching unrelated tickets still collide
in them, and the conflict is meaningless — the correct resolution is always
"regenerate". frankC proposed a **merge driver** for exactly this, and it removes
the conflict class rather than one more failure path.

## Proposed work

1. **A merge driver for `BOARD*.md`** (`.gitattributes` + a driver that runs
   `progress.sh board-md` and takes the result). This is the item with the
   leverage: it should remove the large majority of rebase conflicts, and with
   them most of the rebases that the losses happen during.
2. **Measure before and after.** Count conflicts per push over a day, by file,
   so the claim in (1) is a measurement rather than a plausible story. If
   `BOARD*` is not actually the majority, the driver is the wrong fix and we
   should know that before writing it.
3. **Consider not committing the boards at all**, or committing them from one
   place. A generated artifact in git that every lane rewrites is the root; a
   merge driver is a very good treatment of a self-inflicted wound.

## A fourth shape, from the same night, that no tool fix covers

Not `sync.sh`, and worth recording next to it because it is the same *family*:

**`git add a b c` where one path does not exist aborts the ENTIRE add with a
fatal — and the `git commit` that follows still succeeds, on whatever was staged
before, and prints a success line.** A step failed, the next step succeeded on a
subset, and the aggregate reported success. It cost three commits tonight: one
that landed as a bare rename with none of its content, one that landed with only
a ticket move, and one recovered by `reset --soft`. Nothing was lost — the
working tree still held everything — but each looked complete.

Same shape as symptom 3 and as the size canary's own rule: **failing to do the
thing is not the same as failing loudly, and an aggregate that reports success
after a failed step is the dangerous case.** The habit that avoids it is
`git add -A <dir>` or `git add -u` plus explicit new files, never a hand-written
list that may contain a path a previous step already consumed.

Recorded here rather than in CLAUDE.md because CLAUDE.md is the owner's.

## Not started

Filed rather than begun: `tools/sync.sh` has had three patches from the
coordinator in the last two hours, and a second agent editing it concurrently is
the collision this whole ticket is about. Whoever takes it should confirm the
file is quiet first.
