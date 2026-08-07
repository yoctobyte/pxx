---
summary: "plexus publishes RED runs that never executed (wall 0.0, compiler_sha256 unknown, 0 bench rows), inventing a selfhost-fixedpoint regression that does not reproduce; and the pre-rename `xeon` host entry still holds an open regression nothing can ever clear"
type: bug
track: T
prio: 75
status: done
owner: claude-T@plexus
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

## Log
- 2026-08-07 — resolved, commit 005d32342.

---

## Resolution (Track T, 2026-08-07) — commits `91b270933` + `be4556d59`

**The ticket named the symptom correctly and the cause not at all** — which is
the expected ratio (`devdocs/dev/root-cause-over-microfix.md`). There was no
watcher bug that "publishes RED for jobs that never ran" in isolation. There
was a broken box that could not tell anyone it was broken.

### Root cause

plexus's persistent seed binary had drifted to `021ead850d60`, a mid-bisect
artifact from an old sha. Building from it, stage-1 **deterministically
segfaults on startup** — GP fault at `0x4006ac`, `mov (%rax),%rax` with
`%rax = 0x6e203030317e2073`, which is ASCII (`"s ~100 n"`) from the comment on
`compiler/defs.inc:14`: a source buffer dereferenced as a pointer. 5/5 runs
identical, so not a flaky box; ECC counters 0/0 and no OOM, so not the RAM
anyone would have suspected after a hardware swap. Reseeded from the pinned
stable, HEAD self-hosts here in one round. **Neither the sources nor the
hardware were ever at fault**, which is exactly what the borg control said.

Why it lasted a day: the one recovery path was dead.
`testmgr.report_build_failure()` *writes* a report, and `run_gate()`'s
reseed-and-retry only fired when the report was **missing**. So the box never
reseeded, and every cycle re-published the same failure. That report also
carried `verdict: RED` plus a synthetic failing `selfhost-fixedpoint#00` job —
which diffed to NEW-RED, opened a ledger entry, and handed the bisector
something to narrow down to `4ce9b3fc0974`, an innocent commit.

### Microfix vs overhaul — deliberately, the small overhaul

The ticket asked for one guard at `publish()`. Counting mechanisms first
(rule 3) showed **three** already serving one concept — "this run did not
happen": the missing-report path, the `INVALID` mid-run-compiler-change path,
and now the build-failure path, each with its own soundness argument and only
the first two correct. Adding a fourth special case is what got us here, so:

- the build-failure path stops inventing a verdict (INFRA, **no jobs** — so
  nothing is diffable and no ledger entry or bisect can be manufactured);
- `no_measurement()` is one publish-time refusal covering the whole family,
  keyed on the *shape* of the report rather than on any producer labelling its
  own failure honestly;
- the recovery that should have run all along now fires on both shapes.

Cost: comparable to the asked-for guard. It also closes the neighbouring hole
nobody had filed — a box that is degraded but silent — by making `--status`
report DEGRADED, and DOWN when every live host is degraded. The standing rule
"T is up → offload the matrix" was the amplifier that turned one broken box
into false reds handed to every lane; it must not fire when no box can run.

### Second fault

`--retire-host OLD [--into NEW]`. Renaming a box is not rare, so it is a
general operation rather than a hand-edit. `xeon` retired into `plexus`; its
real `test-core#src:csocket_loopback_b88.c` migrated and now clears normally,
and the manufactured `selfhost-fixedpoint` entry was dropped.

### Gate

`gate.sh quick` GREEN (self-host fixedpoint 41s, testmgr --tier quick 34s).
Track T is proven down, so its full gate was run too: `testmgr --tier full`,
**2100/2101 pass**. The single failure is `test-nilpy#326`
(`test_nilpy_for_two_names_over_a_variant.npy`) — pre-existing, auto-filed
2026-08-07T05:50Z as `regression-test-nilpy-test-nilpy-for-two-names-over-a-variant`
(prio 70), unrelated to this change and owned by another lane.
Unit tests cover the refusal guard, the reseed-once path (including "still
broken after reseed" not looping), and the retire migration and its
idempotence.

### Note for whoever sees this recur

The trigger is a bisect walking far enough back that the seed left behind
cannot compile HEAD. `converge_seed()` iterates for staleness, but it cannot
converge when stage-1 *crashes* instead of merely differing. The reseed now
handles it automatically; if it stops doing so, that is the thing to check
first.
