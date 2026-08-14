---
track: T
prio: 55
type: bug
blocked-by: []
summary: "`testmgr --pin` picks its gate tier from watcher_is_down(), which reads the LOCAL tstate/ — so without a git fetch it reports your own checkout's staleness as Track T being down, escalates to --tier limited, and runs for minutes with the repo lock held while Track T is actually UP"
status: done
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

## DONE 2026-08-14 — options 1 and 3, together; option 2 deliberately not taken

The ticket offered three fixes and asked for a choice. **1 and 3 compose into
one change and cover each other's gap; 2 would have removed a good default.**

**Option 1 — fetch before asking.** `watcher_is_down()` now runs
`git fetch --quiet origin master` (read-only, no working tree touched, 45s cap)
before consulting `twatch --status`, so the answer is about Track T rather than
about this checkout's staleness.

**Option 3 — "cannot tell" means UP.** If the fetch fails for any reason —
nonzero, offline, no remote, git missing — the function returns *not down*
**without consulting the local tstate at all**, and says so on stderr. Asking a
stale tstate after a failed fetch would just reintroduce the bug with an extra
step.

That pairing is the whole fix: option 1 makes the common case correct, option 3
makes every failure of option 1 land on the cheap side. The asymmetry is the
argument — being wrong towards UP costs a matrix sweep Track T performs anyway;
being wrong towards DOWN costs every lane minutes with the repo lock held.

**Option 2 (escalation becomes opt-in) was not taken.** The automatic
escalation is correct *policy* — when Track T really is down, nothing else
sweeps the matrix and breadth has to come from somewhere. The defect was never
the policy, only the evidence it rested on. Making it manual would have traded a
fixable evidence bug for a permanent hole on the day it actually matters.

### The message that nobody saw

`run_pin` already announced its tier with `flush=True`, and that was still not
enough: stdout is a **pipe** under every caller that matters, and readers
typically surface it only at exit — so the one line explaining a ten-minute wait
arrived after the wait, or never, because the run was killed as a hang first. It
now also goes to **stderr**, and only when the tier is not `quick` (no reason to
double-print the common, fast path).

### Measured, on the real path

```
watcher_is_down() = False (2.6s, includes the fetch)
pin gate tier would be: quick
```

2.6 s to get the right answer, against the >10 minutes the stale-tstate
escalation cost.

### Gate

`tools/devtest_pin_gate_tier.py` — 10 checks. The policy in both directions
including explicit-`--tier` override, and then the part that actually broke: a
fetch happens *before* the status question; a fetch that returns nonzero or
raises is treated as UP; and after a failed fetch the local tstate is **not
consulted at all**. That last one is the assertion that would have caught the
original bug.

### Remove the hook rule now

`.claude/hooks/no-full-suite.sh` refuses `tools/testmgr.py --pin` without an
explicit `--tier quick`, as a guardrail while this was open. That rule can go —
the bundled interruptible pin is the nicer command and should be recommended
again. **That is Track A's file**, so it is theirs to remove; flagged here
rather than edited.

## Log
- 2026-08-14 — resolved, commit 1dbdba4e1.
