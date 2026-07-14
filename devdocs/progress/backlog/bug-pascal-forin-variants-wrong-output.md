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

## Acceptance
Byte-identical stdout to FPC for both; unskip both entries.
