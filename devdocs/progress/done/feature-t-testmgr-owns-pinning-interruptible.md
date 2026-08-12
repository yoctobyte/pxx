---
summary: "Move the pin gate into testmgr so pinning is scheduled, resource-aware and INTERRUPTIBLE, instead of a long foreground gate.sh run a dev agent has to babysit"
type: feature
track: T
prio: 60
status: done
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

## DONE 2026-08-12 — `tools/testmgr.py --pin`

One command: gate (`--tier full` as a child, keeping the process-group teardown)
→ `make stabilize-fast` → atomic pin → `git add` of the stable tree.

**Atomicity is a two-phase split, not care.** `make pin` is four separate
mutations and an interrupt between any two leaves a pin nobody can reason about;
the `rm -rf builtin` is the sharp one, because interrupted there the pinned
compiler resolves `uses builtin` against a half-written directory and every
`$(PXX_STABLE)` consumer silently builds against the wrong RTL. So the whole new
pin is staged OUTSIDE the live names (slow, fully interruptible — an abort there
deletes a staging dir and nothing else), then SIGINT/SIGTERM are blocked with
`pthread_sigmask` and the flip is renames only: microseconds, and a signal
arriving inside it is *deferred* rather than delivered into the middle of it.

**Answering the ticket's open question explicitly, as it asked:** this is an
**operator command on a dev box**. The watcher never pins. Face 1's write scope
stays exactly `tstate/`, which is worth more than the convenience of automating
the one step whose blast radius is every other lane.

`stabilize-fast`, not `stabilize` (user, 2026-08-09). Resumability comes from
that being ~35s plus a `.testmgr/pin-state.json` note that skips a gate already
green for this exact sha with a clean tree — so an interrupt costs the gate, not
an hour.

Landmines, both handled: the pin `git add`s the stable tree (the recorded past
miss — a pin nobody else can see), and `compiler/builtin/**` is re-frozen every
time, so a builtin change cannot be pinned without its RTL.

### Gate — met

- **byte-identical to `make pin`**: both run against scratch trees seeded
  identically (`make pin STABLE_ROOT=…` redirects cleanly). `diff -r
  --no-dereference` reports the resulting trees identical — `stable_pinned`, the
  `pinned` symlink and all 7 frozen builtin sources — with `pin.log` differing
  only in the commit field, where the test passed a literal `HEADSHA`.
- **SIGINT leaves no half-applied pin**: `tools/devtest_pin_atomic.py`, three
  cases — applies fully; interrupted while staging leaves the tree byte-identical
  to before; and a SIGINT raised *inside* the critical section is proven not to
  run there (the test asserts the handler has not fired) and is delivered after
  the flip completes.
- CLAUDE.md's gate.sh line now says pin gate, not dev loop.

## Gate

A pin driven through testmgr produces a pin byte-identical to one driven through
`gate.sh` + `make pin`, and SIGINT at several points during it leaves the tree in
a clean, un-pinned state every time.

## Log
- 2026-08-12 — resolved, commit PENDING-COMMIT.
