---
summary: "toperator93.pp compiles but the pxx binary SEGFAULTS (exit 139) — class-operator shape crashes at runtime"
type: bug
prio: 50
---

# toperator93: compiles clean, segfaults at runtime

- **Type:** bug (runtime crash). **Track P/A** (class operators / codegen).
- **Opened:** 2026-07-15 night re-triage (task-conformance-retriage-33).
- pxx compiles library_candidates/fpc-testsuite/tests/test/toperator93.pp
  with --strict-case --strict-operator, the binary exits 139; FPC's runs
  clean. Needs a minimal repro (the test exercises class operators —
  compare toperator91/95's Implicit/Explicit shapes, some already skipped).

## Acceptance
Runs to FPC-identical output; unskip.

## Log
- 2026-07-15 — resolved, commit PENDING.
