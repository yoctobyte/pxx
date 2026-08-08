---
summary: "gate.sh's self-host check compares the hermetic fixedpoint against the LIVE compiler/pascal26, so a concurrent build in the same clone flips it red transiently — testmgr snapshots the binary per run for exactly this reason"
type: bug
track: T
prio: 45
---

# `gate.sh` self-host reads the live `compiler/pascal26`, so a concurrent build flakes it

- **Type:** bug (Track T — `tools/gate.sh`, `tools/selfhost_fixedpoint.sh`)
- **Found:** 2026-08-08, immediately after `bug-t-gate-sh-fixedpoint-does-not-iterate`
  routed `gate.sh` through `tools/selfhost_fixedpoint.sh`.

## What happens

`selfhost_fixedpoint.sh` checks two properties. The second — the anti-Thompson
one — is that the fixedpoint reached from `pinned` must equal `compiler/pascal26`,
*the binary the suite is testing with*. It reads that binary at the **live,
mutable path**.

`compiler/pascal26` is a single mutable path and a prerequisite of every test
target, so any concurrent `make` in the same clone replaces it mid-check. Then:

```
FAIL: the fixedpoint reached from PINNED differs from compiler/pascal26
      /tmp/selfhost-fp-2165496/stage_1a /home/neo/pxx/compiler/pascal26 differ: byte 97
gate: RED
```

Observed once on plexus with **17 other build processes** on the box (the
watcher's clone plus a sibling agent). `make compiler/pascal26` then reported
"up to date", `selfhost_fixedpoint.sh` re-run reported *"converged after 1
round(s) ... agrees with compiler/pascal26"*, and `gate.sh quick` was GREEN.
Nothing was wrong; the binary simply changed underfoot.

## Why it matters

The property is RIGHT and worth keeping — it is the only check that catches a
compiler converging to a *different* self-reproducing fixedpoint. But a gate
that is red for the normal case trains agents to ignore it, which is the exact
complaint that filed `bug-t-gate-sh-fixedpoint-does-not-iterate`. Trading a
deterministic false red for an intermittent one is not a win.

It also lands hardest where clones are shared: the box that runs the watcher is
also the box an agent gates on.

## Fix shape

`tools/testmgr.py` already solved this — it takes **the run's own copy** of the
compiler (`RUN_TMP`) precisely because "any unrelated make can replace it
mid-run". Do the same here: snapshot `compiler/pascal26` once at the start of
`selfhost_fixedpoint.sh` and compare against the snapshot, so the answer
describes one instant.

Cheaper alternative if a snapshot is unwanted: re-read and re-compare once on
mismatch, and report the flake distinctly (`compiler/pascal26 changed during
the check — rerun`) rather than as a self-host failure. That keeps the signal
honest without a copy, but it is a retry, not a fix.

## Gate

`gate.sh quick` green; a devtest that replaces `compiler/pascal26` mid-check
must not produce a self-host FAIL.
