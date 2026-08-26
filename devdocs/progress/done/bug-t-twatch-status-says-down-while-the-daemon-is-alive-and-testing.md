---
track: T
prio: 55
type: bug
blocked-by: []
summary: "tools/twatch.py --status exits 1 (DOWN, 'run your own full gate') on the same box and at the same moment that tools/trackt.py health reports OK with a live daemon in phase=testing. The DOWN verdict is a pure staleness heuristic — newest commit untested for > 45 min — so a productive night of pushes, or a loaded box, manufactures it. CLAUDE.md makes either command's DOWN the trigger for a 10-minute full gate, so a false DOWN costs every dev agent ten minutes per fix."
owner: pxx-aa
---

# `twatch --status` reports DOWN while the daemon is alive and testing

- **Type:** bug (false alarm with a documented, expensive consequence) —
  **Track T** (`tools/twatch.py` is T's file; filed by Track A, not fixed here)
- **Status:** done
- **Opened:** 2026-08-21

## Measured, same box, same minute

```
$ tools/twatch.py --status ; echo rc=$?
tstate: host plexus  last d7b5113da47e RED (native, 2026-08-21T18:35:50Z)
tstate: DOWN — e799fa5f5db2 untested for 53 min (> 45 min grace); run your own full gate
rc=1

$ tools/trackt.py health
trackt health: OK
  - daemon 397738, phase=testing, publishing clean
```

`tools/gate.sh` agreed with the second one, unprompted, on every run that hour:
*"NOTE Track T tooling is running here (2 process(es)), load 5.49"*.

## Why it fires

`status()` is deliberately a no-ping heuristic — *"a watcher is considered UP
iff every commit older than the grace window is tested by some host"* — and its
docstring already lists two ways the inputs go stale. This is a third, and it is
the opposite of staleness: the watcher is **alive and mid-run**, and the tree
moved faster than one cycle. Eight pushes in about two hours on a box also
running the watcher (load 5.5, every compile 2-3x slower) is enough. The
heuristic cannot tell "nobody is testing" from "the tester is busy with the
commit before yours", and those two have opposite correct responses.

## Why it is worth fixing rather than living with

CLAUDE.md's per-fix loop names this exact command as the authority:

> **The one exception: Track T is PROVEN down** — `tools/twatch.py --status`
> exit 1, or `tools/trackt.py health` reporting DOWN. Then run your lane's full
> gate first.

So a false DOWN converts a ~30-second gate into a ~10-minute one for every fix,
for every agent, until the watcher catches up — and the busier the tree is (the
case where throughput matters most), the more likely it fires. It also trains
agents to disbelieve the command, which is worse than the ten minutes.

## Suggested shape (T's call)

The information that settles it is already local and already read by the sibling
command: a live daemon with a recent heartbeat means T is UP-but-behind, not
down. Three distinguishable verdicts rather than two —

- **UP** — coverage current, offload.
- **BEHIND** — daemon alive, newest commits not yet reached. Offload; say how
  many commits and how old, do not tell the reader to run a full gate.
- **DOWN** — no live daemon AND stale coverage. The existing message.

...with the exit code staying 0 for BEHIND, since the exit code is what
CLAUDE.md and the agents branch on.

## Not filed as urgent

Nothing is broken in the product and no test is red because of it; the cost is
agent time and trust in the tool. Track A worked around it tonight by reading
`trackt.py health` (OK) and continuing on quick gates, per the user's standing
instruction that quick gating is what a development track runs.

## Resolved 2026-08-26 (pxx-aa, Track T)

Implemented as the ticket's suggested shape, three verdicts:

- **UP** — coverage current.
- **BEHIND** — daemon alive, newest commits not yet reached. **Exit 0**, says
  how stale and explicitly *"do NOT widen your gate"*.
- **DOWN** — unchanged message, exit 1.

The exit code is what CLAUDE.md and every agent branch on, so BEHIND returning
anything but 0 would have been the same bug with better wording.

### BEHIND is claimed on evidence, not on a second heuristic

`local_daemon()` requires **both** a fresh heartbeat (`HEARTBEAT_FRESH_SECS`,
300s — the daemon rewrites it every 30s mid-gate, so this is already several
missed beats) **and** a live pid whose `/proc/<pid>/cmdline` contains
`twatch.py`. Neither alone: a heartbeat file outlives the process that wrote it,
and pids are recycled. Clone discovery is the same order `trackt health` uses
(`$TRACKT_CLONE`, `~/.config/trackt.path`, `~/trackt-watch`) — the information
that settles this was always local and the sibling command was always reading
it.

**No clone on this box returns None**, so an agent on another machine still gets
DOWN. That is the honest answer there: we genuinely cannot tell, and inventing
an optimistic BEHIND would be the mirror of the bug.

### Seen going both ways, live

```
$ tools/twatch.py --status --grace 0
tstate: plexus daemon is ALIVE (phase=testing, heartbeat 0m ago) but BEHIND —
        10a186faa689 untested for 1 min. … do NOT widen your gate.
tstate: UP (behind) — offload the matrix to T
rc=0

$ TRACKT_CLONE=/nonexistent-clone tools/twatch.py --status --grace 0
tstate: DOWN — 10a186faa689 untested for 1 min (> 0 min grace); run your own full gate
rc=1
```

Same tree, same second; the only difference is whether a live daemon is
findable. `tools/twatch_behind_vs_down_devtest.py` guards the four rejection
cases (stale beat, dead pid, live-but-unrelated pid, no clone) plus the exit
code.

The structure is deliberately the same as the existing breadth-in-flight case
directly above it, which had already drawn this distinction for one specific
cause. This generalises it: *a busy tester is not a stalled one*, whatever it
happens to be busy with.

## Log
- 2026-08-26 — resolved, commit PENDING-COMMIT.
