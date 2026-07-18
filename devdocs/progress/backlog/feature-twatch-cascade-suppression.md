---
prio: 40
---

# twatch: suppress downstream auto-filing when a root job (fpc-bootstrap) is red

- **Type:** feature — **Track T** (watcher behavior). Opened by fable-O after
  the 2026-07-18 cascade.
- **What happened:** one missing FPC-seed forward turned `fpc-bootstrap` red;
  the next watcher pass auto-filed **939** regression tickets — every
  FPC-dependent job (lib-fpc-clean, test-asm suite, FPC-built test-core sweep)
  filed its own. One root cause, 939 files of noise (bulk-swept to rejected/,
  see [[regression-cascade-f5c8fbec-fpc-bootstrap]]).
- **Ask:** teach twatch job dependencies (or at least the one big edge:
  `fpc-bootstrap` red ⇒ fold all FPC-dependent reds into the fpc-bootstrap
  ticket as a cascade list instead of filing each). A red ROOT job should file
  ONE ticket naming the cascade set.
- **Gate:** T tooling gate (`tools/testmgr.py --tier full` green) + a scratch
  bare-repo dry run of the filing path.

## Resolution (fable-O, same evening — user-directed)

Implemented as a threshold, not a dependency graph: `file_stub_tickets` now
routes any sweep with > CASCADE_THRESHOLD (10) new reds to
`file_cascade_ticket` — ONE ticket keyed on the bad sha (dedup via the same
any-bucket check), listing the full job set, naming root-cause suspects when
`fpc-bootstrap`/`selfhost-fixedpoint` are in the set. Small sweeps keep
per-job stubs. Scratch-harness verified: 3-red sweep → 3 stubs; 50-red sweep
(incl. fpc-bootstrap) → 1 cascade ticket with the root named; same-sha rerun
→ no duplicate. Full dependency modeling stays future work if the threshold
ever misroutes.
