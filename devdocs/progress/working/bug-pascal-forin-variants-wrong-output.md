---
summary: "for-in variants run to exit 0 with SILENT wrong output: tforin14 prints element ADDRESSES, tforin25 prints nothing where FPC prints values"
type: bug
prio: 55
---

# for-in: two variants produce silent wrong output (exit 0)

- **Type:** bug (silent wrong values). **Track P** (for-in lowering).
- **Opened:** 2026-07-15 night re-triage (task-conformance-retriage-33).
- tforin14.pp: prints pointer-looking numbers (4229786 4239850 ...) where FPC
  prints the element values (1 2 9 / 3 4 5 ...) — the loop var appears to be
  bound to an ADDRESS, not the element.
- tforin25.pp: prints nothing where FPC prints four `0` lines — a loop shape
  that never iterates.
- Both exit 0, so the conformance runner counts them "pass" — the wrong-output
  class the skip-file header warns about. Cluster: likely one for-in
  variant-dispatch bug; minimize from the two tests before fixing.

## Progress (2026-07-15 night)

Two sub-bugs FIXED (see fix commit): non-0-based static-array bounds and
N-D outer-dimension iteration (test_forin_bounds_nd). RESIDUALS:
- tforin14: `for r in a` where a is an OPEN-ARRAY parameter of an array
  type still prints ADDRESSES — the open-array desugar path.
- tforin25: still prints nothing where FPC prints four 0 lines — shape
  not yet minimized.

## Acceptance
Byte-identical stdout to FPC for both; unskip both entries.
