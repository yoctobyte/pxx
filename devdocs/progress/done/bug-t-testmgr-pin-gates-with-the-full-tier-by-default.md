---
track: T
prio: 70
type: bug
blocked-by: []
summary: "`testmgr.py --pin` with no --tier gates with the FULL tier (2305 jobs, the whole cross-target matrix) while holding the repo lock — so the documented operator pin command blocks every other lane for an hour. run_pin's own docstring quotes the 2026-08-09 decision that all-target verification belongs to a RELEASE, not to a pin; the stabilize half honours it and the gate half does not"
status: done
---

# `testmgr --pin` gates with the FULL tier by default

- **Type:** bug (a default at odds with the documented intent) — **Track T**
- **Found:** 2026-08-13, by an operator running the pin at the end of an A+N
  session. Measured, not inferred.

```python
# tools/testmgr.py, run_pin(), ~line 2581
tier = args.tier or "full"
```

`python3 tools/testmgr.py --pin` therefore runs **`--tier full`** — 2305 jobs,
every cross target — before it stabilizes and pins. Two operators (the human at
the terminal and the agent) both killed it as a hang; it was not hanging, it was
doing an hour of work that nothing asked for.

## Why this is a defect and not a preference

`run_pin`'s own docstring quotes the decision it then contradicts:

> *(stabilize-fast, not stabilize -- user, 2026-08-09: all-target verification
> belongs to a RELEASE, not to a pin.)*

The **stabilize** half honours that and runs `stabilize-fast` (~35–41s
measured). The **gate** half above it still defaults to all-target, so the cost
the 2026-08-09 decision removed came back through the other door — and this time
with the repo lock held, which the code states plainly:

> *The repo lock is held for the WHOLE pin, gate included: a concurrent
> [build] ... (nothing else may build meanwhile).*

So the default blocks every other lane for the duration. That is precisely the
"other tracks — and the human — are BLOCKED while a pin runs" cost CLAUDE.md
weighs when it tells Track A to use `stabilize-fast`.

## Measured, 2026-08-13

| step | time |
| --- | --- |
| `make stabilize-fast` (self → next → fixedpoint, byte-identical) | **41s** |
| `make pin` (symlink move + freeze 7 builtin RTL sources) | **0.07s** |
| `testmgr --pin`'s gate at the default tier | full — 2305 jobs, never allowed to finish |
| `gate.sh quick` (the documented PIN GATE) | ~30s |

## The gap this leaves today

Neither available option is the one an operator wants:

- `make stabilize-fast && make pin` — fast (41s) and **completely ungated**;
- `testmgr --pin` — gated and **an hour with the lock held**.

"Cheap gate, fast pin" is what the pin philosophy already describes, and it is
the combination you cannot currently ask for by default. (v267 was pinned via
the first option on 2026-08-13; the safety came from the operator having run
`gate.sh quick`, `make test-nilpy` and `--tier limited` 1801/1801 beforehand,
not from the command.)

## Proposed fix

Default `--pin`'s gate to **quick**, and keep `--tier full` as the explicit
opt-in for a RELEASE pin:

```python
tier = args.tier or "quick"
```

That matches `tools/gate.sh quick` being named THE pin gate in CLAUDE.md, keeps
`--pin --tier full` available for a release, and leaves the checkpointing
(`gated_sha`) untouched. Worth deciding alongside it:

- should `--pin` print the tier and its expected duration before starting? Both
  operators read "no output for minutes" as a hang, which is a UX defect
  independent of which tier is right;
- the `--tier limited` middle ground may be the better default for a pin when
  Track T's watcher is DOWN, since then nothing else is sweeping the matrix at
  all. If so, that conditional belongs in the tool, not in an operator's head.

## Workaround until then

`python3 tools/testmgr.py --pin --tier quick` — `--tier` IS honoured with
`--pin` (it is only *required* for a plain run), so the gated fast pin exists
today; it is just not what the bare command does.

## Gate

`tools/testmgr.py --tier full` green (Track T's own gate for tooling changes),
with the tool exercised the way Track T's rules prescribe — QUICK tiers and a
scratch bare repo, never long runs. Assert both directions: the bare `--pin`
gates quick, and `--pin --tier full` still gates full.

## Also noticed, trivial and separate

`tools/trackt.py` is not executable — `tools/trackt.py health` answers
"Permission denied" and needs `python3 tools/trackt.py health`. A `chmod +x`,
worth folding into whatever touches Track T's tooling next rather than its own
ticket.

## FIXED 2026-08-13 — by the agent that wrote the defect

Accepted in full; the report is correct and the reasoning is the one that
should have been applied when `--pin` was written the day before. `run_pin`
quoted the 2026-08-09 decision in its own docstring and then contradicted it one
branch later.

- `pin_gate_tier(explicit, down)` — split out as a pure function precisely so
  the Gate's "assert both directions" is a unit test rather than an hour-long
  run. Bare `--pin` gates **quick**; explicit `--tier` always wins.
- **The Track-T-down conditional is now in the tool**, as the ticket suggested it
  should be: `watcher_is_down()` uses the documented test (`twatch --status`
  exit 1 — not "slow", not "feels stale"), and escalates the default to
  `limited`, saying so and naming the override. Any error reaching that probe
  counts as NOT down, so a failed subprocess can never silently buy an hour.
- **Every phase now announces itself and its expected cost** — `gate — tier
  quick (~30s)`, `stabilize-fast (~40s ...)`, `applying the pin
  (uninterruptible from here — microseconds)`. This was the real reason two
  operators killed it: silence, not duration.
- `chmod +x tools/trackt.py` — folded in as the ticket asked.

Verified both directions end to end, with the gate child's argv captured rather
than executed: bare → `--tier quick`, `--tier full` → `--tier full`. Pinned as a
case in `tools/devtest_pin_atomic.py`, run against a scratch tree per Track T's
"QUICK tiers and a scratch repo, never long runs" rule.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
