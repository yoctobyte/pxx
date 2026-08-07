---
summary: "plexus publishes RED runs that never executed (wall 0.0, compiler_sha256 unknown, 0 bench rows), inventing a selfhost-fixedpoint regression that does not reproduce; and the pre-rename `xeon` host entry still holds an open regression nothing can ever clear"
type: bug
track: T
prio: 75
---

# plexus publishes false REDs, and the renamed `xeon` host holds a regression forever

- **Type:** bug (Track T — `tools/twatch.py`, tstate host ledger) — **urgent**
- **Found:** 2026-08-07 by `claude-AN@borg`, while checking post-hardware-swap
  stability before picking up Track A+N work.
- **Filed by a non-T lane on purpose:** T owns the tool, so this is filed, not
  fixed. It is urgent because the watcher is currently the only lane reporting
  breadth, and right now it is reporting breakage that is not there.

## Two faults, one cause window (the GPU swap + the `xeon` → `plexus` rename)

### 1. plexus reports RED for jobs that never ran

`devdocs/progress/tstate/reports/20260807T144547Z-b0cbeba-plexus.md`:

```
wall: 0.0
compiler_sha256: unknown
verdict: RED

## STILL-RED
- selfhost-fixedpoint#src:compiler/compiler.pas — compiler/compiler.pas
```

A genuine self-host fixedpoint comparison takes tens of seconds and yields a
hash. `wall: 0.0` with `compiler_sha256: unknown` means the job **did not
execute** — yet it is published as a verdict, and the ledger then bisected it
to a `bad=` commit (`4ce9b3fc0974`, the managed-block-kind-word pin v247).

The bench job fails the same way: `bench b0cbeba6029d RED (0 bench rows, 550
conf)` — zero rows produced, published as RED rather than as "did not run".

**Control (this is the part that makes it a false red):** at
`9e9509e96` — a *descendant* of the accused `4ce9b3fc0974` — on borg:

```
tools/gate.sh quick
  PASS  self-host fixedpoint  (21s)
  PASS  testmgr --tier quick  (19s)
gate: GREEN
```

The compiler reproduces itself byte-identically. The accused regression does
not exist.

**The ask:** a run that produced no measurement must publish as INFRA/SKIP, not
as RED. A `wall == 0.0` or `compiler_sha256 == unknown` verdict should be
refused at `publish()` time. As it stands a broken box silently converts into
"master is broken", and the bisector then manufactures a `bad=` sha — which is
worse than silence, because it points a lane at an innocent commit.

### 2. The renamed host holds an open regression that nothing can clear

`xeon` was renamed to **plexus**. The ledger still carries `xeon` as a distinct
host, and `tools/twatch.py --status` says:

```
tstate: host xeon  ... [QUIET 2d17h — not publishing]
tstate:   1 open regression(s) held with xeon — nothing can clear them until it publishes again
```

held item: `test-core#src:csocket_loopback_b88.c` (bad `330f62af78d0`, 58
commits in range).

Nothing will ever publish as `xeon` again, so that regression is **permanently
unclearable** — a phantom that will sit in every status readout indefinitely.
`borg` is a real quiet host (it was down for the swap; it is back up now) and
should recover on its own; `xeon` cannot.

**The ask:** a way to retire or alias a host — `xeon` → `plexus` — that either
migrates its open regressions to the new name or closes them out. Worth a
general rule, since renaming a box is not a rare event.

## Why urgent

Both faults point the same direction: the watcher currently makes master look
broken when it is not. The standing guidance is "T is up → offload the matrix
to T", and `--status` does report `UP` — so a lane that follows the rule gets
false reds with a plausible bad-commit attribution attached. A core-job red is
also a documented revert candidate, so this can cost an innocent commit.

## Gate

Track T's own: `tools/testmgr.py --tier full` green, plus a check that a
zero-wall / unknown-hash run does not publish a RED verdict.

Related: [[bug-t-a-self-healed-red-leaves-a-permanent-prio-70-stub-at-the-head-of-the-queue]]
(same family: the ledger keeping a red alive past its truth).
