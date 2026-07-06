---
prio: 45  # auto
---

# Emission size — reachability-gated dead-code elimination (umbrella)

- **Type:** feature (codegen / optimization) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30 (merge of feature-lazy-standard-unit-emission +
  chore-runtime-emission-size, found redundant in triage)
- **Relation:** the concrete passes here would be hosted by
  [[feature-optimization-levels]]'s pass framework (kept separate; cross-linked).

## Goal

Shrink emitted binaries by emitting only reachable code. Two overlapping fronts,
unified here:

1. **Routine-level DCE for `uses`-unit bodies** (was feature-lazy-standard-unit-
   emission): a `uses textfile`/`builtin` pulls in whole unit bodies even when only
   one routine is called. `hello.pas` still emits ~31.6 KB vs a ~29 KB reachable
   baseline. Emit a unit routine only if reached from the program entry.

2. **Finer runtime-support emission** (was chore-runtime-emission-size): the
   implicit runtime helpers (string/dynarray/managed/exception support) are emitted
   coarsely; gate each on actual use.

Both are the same mechanism: build a call/reachability graph from the entry point
and skip unreferenced routine bodies. Do it once, cover both fronts.

## Acceptance

`hello` (and other minimal programs) shrink measurably (toward the ~29 KB
baseline) with no behavior change; self-host byte-identical; `make test` + cross
green. Ideally lands as an `-O`-gated pass under [[feature-optimization-levels]].

## Notes
- Merged from two redundant tickets (2026-06-30 triage). History in git.
