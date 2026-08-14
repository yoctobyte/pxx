---
track: T
prio: 55
type: bug
blocked-by: []
summary: "`testmgr --pin` picks its gate tier from watcher_is_down(), which reads the LOCAL tstate/ — so without a git fetch it reports your own checkout's staleness as Track T being down, escalates to --tier limited, and runs for minutes with the repo lock held while Track T is actually UP"
status: backlog
---

# `testmgr --pin` escalates its gate on a stale local `tstate/`

- **Type:** bug (silent multi-minute stall, blocks every lane) — **Track T**
  (owns `tools/testmgr.py`)

## What happened, measured

2026-08-14, pinning after a `compiler/builtin/pyeval.pas` change. `testmgr
--pin` ran for over ten minutes; the process tree showed it executing
`test_asm_dis_self` and the **uforth differential, whose timeout alone is 900s**
— i.e. a tier well past `quick`. It was killed as a hang, twice (once at a
2-minute command timeout, once deliberately).

Immediately afterwards, with a `git fetch` first:

```
tstate: host plexus  last c32f84a9423b GREEN (native, 2026-08-14T09:24:54Z);
                     full through e44da6c5e6a2 GREEN
tstate: UP — commits through c32f84a9423b tested; offload the matrix to T
twatch exit=0
```

**Track T was UP the whole time.** The same pin then completed as
`make stabilize-fast && make pin` in ~35 seconds.

## Cause

`run_pin` chooses its gate tier with `pin_gate_tier(args.tier, down)` where
`down = watcher_is_down()`. `pin_gate_tier`'s own docstring is right about the
policy — quick by default, `limited` only when "Track T is PROVEN down, so
nothing else is sweeping the matrix". The defect is in the **evidence**:
`watcher_is_down()` reads the local `tstate/`, and CLAUDE.md already documents
that this "reports your own checkout's staleness" unless you `git fetch` first.

A dev checkout is stale most of the time. So the escalation — designed as a rare
exception — fires on the common path, and the expensive branch is the default in
practice.

This is the same lesson as
`bug-t-testmgr-pin-gates-with-the-full-tier-by-default`, one level down: that
one fixed the default tier, this one is the *condition* that overrides it being
unreliable in the same direction.

## Fix — options, not a prescription

1. **`git fetch` (or `git fetch --quiet origin master`) before asking**, so the
   answer is about Track T rather than about your checkout. Cheapest, and makes
   the existing policy mean what it says.
2. **Make escalation opt-IN** (`--tier limited` explicitly) and never automatic.
   The exception is rare and the operator is present; a printed hint beats a
   silent ten minutes.
3. **Treat "cannot tell" as UP.** Being wrong that way costs a matrix sweep that
   Track T will do anyway; being wrong the other way costs every lane minutes.

Whichever is chosen, **print the tier and its expected cost before starting** —
`run_pin` already does this, but the message went into a pipe and was never seen
because the caller had it buffered. Worth flushing to stderr as well.

## Guardrail already in place

`.claude/hooks/no-full-suite.sh` now refuses `tools/testmgr.py --pin` unless it
carries an explicit `--tier quick`, and points at `make stabilize-fast && make
pin`. CLAUDE.md's pinning bullet says the same. **Remove the hook rule when this
is fixed** — the bundled interruptible pin is genuinely the nicer command and
should be the recommended one again.

## Gate

Track T's own: `tools/testmgr.py --tier full` green for tooling changes, tested
against a scratch bare repo rather than a long run.
