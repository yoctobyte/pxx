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

## Progress 2 (2026-07-15, agent-A)

**tforin25 FIXED** (commit c16db957) — three distinct silent bugs, each isolated:
1. Record enumerator was modelled as a tyClass pointer, not an embedded record
   value (advancedrecords GetEnumerator returns a record by value) → MoveNext
   mutated a stale temp, loop ran zero times.
2. `Length` of a static-array FIELD folded to 0 (the fold only handled AN_IDENT
   arrays) → `FIndex < Length(FArr)` was `< 0`.
3. Whole static-array FIELD-to-FIELD copy (`Result.FArr := F`) truncated to one
   element (the whole-array IR_COPY_REC path only fired for AN_IDENT arrays).
Regression: test/test_forin_record_enumerator_b355.pas.

**tforin14 STILL OPEN** — its residual is the aggregate-element dynamic-array
gap, a feature-sized multi-layer fix now fully reconned under
[[bug-pascal-openarray-of-array-param-marshal]] (see its "Recon 2"). This ticket
is blocked on that feature for byte-identical parity.

## Acceptance
Byte-identical stdout to FPC for both; unskip both entries.
(tforin25 done; tforin14 blocked on the aggregate-element dynarray feature.)

## Resolution (2026-07-15, agent-ACP — with f6a843f0)

tforin14's blocker landed: the aggregate-element dynamic-array / open-array row
model ([[bug-pascal-openarray-of-array-param-marshal]], commit f6a843f0) plus
the for-in open-array-param Length fix (the ArrLen=1000 placeholder was used as
a static bound). Verified BOTH tests byte-identical to FPC (tforin14: '1 2 9 /
3 4 5'; tforin25: four 0 lines); conformance.tsv entries flipped to pass.
Regressions: test/test_forin_record_enumerator_b355.pas (tforin25),
test/test_dynarray_of_fixed_array.pas check 13 (tforin14 shape).


## Log
- 2026-07-15 — resolved, commit f6a843f0.
