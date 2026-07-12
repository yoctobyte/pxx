---
prio: 55  # cold-start insurance: cheap to run, expensive to discover late
---

# testmgr: FPC-bootstrap canary — catch seed rot before it matters

- **Type:** feature / regression coverage — **Track T** (`tools/testmgr.py`)
- **Status:** done
- **Opened:** 2026-07-12, found by accident while building a Track A change.

## Symptom

`make bootstrap` (the FPC-seeded cold-start path) is **red on master** and has
been for an unknown length of time — nobody noticed, because day-to-day work
rebuilds from the self-hosted seed (`compiler/pascal26`), never from FPC:

```
parser.inc(1063,11) Error: function header "ParseGenericTemplateNamed" doesn't match forward : var name changes templateName => templateNameIn
parser.inc(1065,15) Error: Duplicate identifier "templateName"
parser.inc(1072,19) Error: Identifier not found "templateNameIn"
parser.inc(1636,19) Error: Identifier not found "OrdinalNameToTk"
```

Confirmed on a clean checkout with no local changes (4 errors on stock master).

## Why it matters

The FPC seed is the **cold-start path**: the only way to rebuild the compiler on
a box that has no blessed `pascal26` binary, and the escape hatch if a
self-hosted binary is ever lost or corrupted. It is load-bearing precisely when
everything else has gone wrong — a bad moment to discover it has rotted.

Individually these breaks are trivial (a forward declaration whose parameter got
renamed; a routine that moved). That is the point: they are **cheap to fix the
day they land and archaeology a year later**, because the drift is silent. The
compiler's own source keeps evolving in the pxx dialect, and pxx is laxer than
FPC in places, so it drifts out of FPC-compatibility with no signal.

## Fix

Add an **FPC-bootstrap canary job** to the testmgr matrix:

- Runs `$(FPC) $(FPCFLAGS) -o<tmp> compiler/compiler.pas` — the *first* line of
  `make bootstrap` only. Compile-only, no self-host fixedpoint, no full
  bootstrap chain: catching the FPC-accepts-the-source property is the whole
  point, and that first command is the entire signal.
- Cheap enough for a regular tier (it's one FPC compile).
- Skips cleanly when `fpc` is not installed, like the corpus jobs skip when
  their sources are unfetched — the watcher box may not have FPC.
- A red here should file/refresh a ticket in the owning lane (**Track A** — it's
  `compiler/**` source drift), not block dev pushes: nothing day-to-day depends
  on the FPC path, so this is a *notice*, not a gate.

## Acceptance

- testmgr runs the FPC compile of `compiler/compiler.pas` as its own job and
  reports it red today (it should — master is broken right now).
- Job skips, not fails, on a box without FPC.
- The four errors above get fixed under Track A and the canary goes green.

## Notes

Sibling of [[feature-testmgr-memory-cap]] — both are "testmgr should have caught
this" gaps found the same day. Separately noticed while running `--tier limited`:
`test-core#555` / `#556` (`test_c_argspill`, `test_c_lazycasing`) are red on
stock master too, and look like the cross-job shared-artifact hazard testmgr.py
documents at line 301 — one job builds `libspill.so` / `liblazycasing.so` into
its own scratch dir, the consumer job runs with a different scratch and cannot
dlopen it. Worth its own Track T ticket if it isn't already known.

## Log
- 2026-07-12 — resolved, commit 6ec9cefb.
