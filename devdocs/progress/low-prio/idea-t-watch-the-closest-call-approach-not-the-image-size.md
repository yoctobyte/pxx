---
slug: idea-t-watch-the-closest-call-approach-not-the-image-size
track: T
prio: 40
type: idea
status: low-prio
found: 2026-09-01
found-by: frankS
owner: ""
blocked-by: []
summary: "The obvious guard against xtensa reach failures is a watch on image size, and it would NOT WORK: measured 2026-09-01, the 622444B call0 image FAILS and the 556908B windowed image BUILDS, both over CALL8's 524288 -- the larger one is the one that builds, because the condition is max caller->callee distance and size is only a proxy. Watch closest approach to +-512 KiB across call sites instead; the xtensa backend already computes it to emit its refusal, so this is a report, not a new analysis, and it changes no codegen."
---

# watch the closest CALL APPROACH, not the image size

**Filed by frankS 2026-09-01**, written up by frankB, out of the triage in
[[feature-a-xtensa-should-not-need-a-flag-to-build-a-large-image]].

## The trap this exists to avoid

[[bug-a-the-esp32-bare-image-doubled-in-code-and-grew-half-again-in-bss]]
complains that nothing watches image size, and the natural response is to add
that watch. **On the evidence it would have stayed GREEN through a real
regression.**

| ABI | code size | verdict |
| --- | --- | --- |
| call0 | 622444 B | **FAILS** the CALL8 reach |
| windowed | 556908 B | **builds** |

Same source, same commit, both over 524288, and the LARGER image is the one that
builds. `4419e1aa7` then flipped the call0 arm from building to refusing **while
changing the code size by zero bytes** — it moved `__pxx_run_finalizers` to the
image tail while its earliest caller stayed at 59154.

So a size watch is a guard aimed at the wrong quantity. It would not have fired,
and being green it would have been read as evidence.

## What to watch instead

**Closest approach to the reach limit across all call sites** — i.e.
`max(|call_site - callee_body|)` per image, reported as a number and as a
percentage of 524288.

The cheap part: **the xtensa backend already computes this.** It has to, to emit
`the forward call to X at code offset N cannot reach its body at M`. This is
plumbing an existing number out to a report, not a new analysis pass, and it
touches no codegen.

## Why it is worth doing rather than waiting for the real fix

It is far cheaper than either candidate on the parent ticket (veneer pool /
two-pass), and unlike both it is **non-invasive** — a measurement, not a change
in what we emit. It also turns a hard build refusal that lands on whoever is
sweeping into a trend anyone can see coming, which matters because the
population is growing on purpose: hosted xtensa is increasingly used as a
differential oracle, so the number of programs compiled for it only goes up.

## What it owes

- A **positive control**: an image known to be within a few KB of the limit,
  asserted to report as such. A watch that cannot report "close" is not a watch.
- A decision on where the number lands — a tstate column, or a line in the
  cross-target report. T's call.
- It should report the closest approach even on a **successful** build. The
  whole value is the warning before the refusal.

## Deprioritised 2026-09-02 — the Track T tooling backlog was cut as a pile

**This ticket is not being called wrong.** It was moved as part of a pile, not
judged individually, and nothing here disputes its finding.

Owner decision. 73 of the 74 open `track: T` tickets were filed between
2026-08-31 and 2026-09-02, 58 on one day. The pile was too large to work through
and returned almost nothing, and a ticket nobody will fix does not sit neutrally
— it stays in the ranker forever at zero value, which is the argument CLAUDE.md
already makes for a terminal folder over a low prio.

Four were kept in the ranker on a purely structural test — an active umbrella or
a hard `blocked-by:` edge from live work:
`umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**Kept, not deleted, for two reasons:** so the finding is not rediscovered and
refiled from scratch by the next agent who trips over it, and so it can be pulled
back if what it touches becomes load-bearing.

**To revive it:** move it to the owning lane's backlog, set `status: backlog`,
and say in the ticket WHAT CHANGED to make it matter now. Restoring it because it
reads well is how the pile comes back.
