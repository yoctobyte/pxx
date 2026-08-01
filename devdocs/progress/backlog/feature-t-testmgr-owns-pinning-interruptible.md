---
summary: "Move the pin gate into testmgr so pinning is scheduled, resource-aware and INTERRUPTIBLE, instead of a long foreground gate.sh run a dev agent has to babysit"
type: feature
track: T
prio: 60
---

# testmgr should own pinning, and pinning must be interruptible

- **Type:** feature (Track T) — **Track T**
- **Opened:** 2026-08-01, from a direct call: pinning is fine to hand to testmgr
  **as long as it is interruptible**.

## Context

`tools/gate.sh` is the **pin gate** — the heavyweight run that blesses a stable
binary. It is not the dev loop, and the new dev-track rule makes that split
sharp: dev tracks build (~12s, which already includes the byte-identical
self-host fixedpoint) and push; breadth is T's.

Pinning is the one step that must stay properly gated, because
`stable_linux_amd64/default/pinned` is the ground Track B and every
`$(PXX_STABLE)` consumer builds on. A red master is cheap and recoverable; a bad
**pin** silently poisons another lane for hours. So: push freely, pin
deliberately.

That makes pinning a scheduled, resource-aware, long-running job — which is
exactly what testmgr already is, and what a foreground shell script is not.

## Asked for

1. A pin path in `testmgr` (e.g. `--pin`, or a `pin` tier) that runs the full
   gate and, on green, performs `stabilize` + `pin` and stages
   `stable_linux_amd64/**`.
2. **Interruptible**: SIGINT tears down cleanly, kills job process groups, and
   leaves NO half-applied pin — either the pin completed or the tree is
   untouched. testmgr already does clean process-group teardown for its jobs
   (`twatch.kill_child` relies on it); the new part is making the
   stabilize/pin step itself atomic with respect to interruption.
3. Resumable or cheaply restartable, so an interrupt does not mean redoing an
   hour.

## Landmines to respect

- `make pin` must `git add` the stable tree — recorded in memory as a real past
  miss (`pin must git-add stable`). An automated pin that skips it produces a
  pin nobody else can see.
- A `compiler/builtin/**` change requires stabilize+pin for the gate fixedpoint
  to be meaningful at all; the pin path should know that rather than leaving it
  to a human to remember.
- Pinning writes to the repo, so if this runs on the watcher host it is the ONE
  thing that breaks Face 1's "writes only `tstate/`" rule. Decide explicitly
  whether pinning is a separate invocation on a dev box or a new,
  clearly-scoped watcher capability — do not let it leak in by accident.

## Also fix while here: gate.sh's role is mis-documented

CLAUDE.md presents gate.sh as the everyday gate — *"Run the gate with
`tools/gate.sh` (quick | lib | full | check), and background THAT"* — which
reads as the dev loop. That is what pulls agents into 554s runs between edits;
it happened twice in one session on 2026-08-01. gate.sh's own header and that
CLAUDE.md line should both say plainly: **pin gate, not the dev loop.** The dev
loop is `make compiler/pascal26` plus your repro.

Related: [[feature-t-quick-gate-must-be-quick-and-gate-lines-must-not-name-long-suites]].

## Gate

A pin driven through testmgr produces a pin byte-identical to one driven through
`gate.sh` + `make pin`, and SIGINT at several points during it leaves the tree in
a clean, un-pinned state every time.
