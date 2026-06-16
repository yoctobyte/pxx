# Multidimensional fixed arrays

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-16 (found via conformance feature-probing)

## Gap

Neither multidim fixed-array syntax parses:

```pascal
var m: array[0..2, 0..2] of Integer;   { Expected: ] }
var m: array[0..2] of array[0..2] of Integer;   { Expected: begin }
```

and the corresponding `m[i, j]` / `m[i][j]` indexing. FPC accepts both and they
are common in user code. Single-dimension fixed arrays and nested *dynamic*
arrays both work today; only nested *fixed* arrays are missing.

## Scope

- Parse `array[lo..hi, lo2..hi2] of T` and `array[..] of array[..] of T` in the
  type grammar (var section, type decls, params).
- Row-major layout; element offset `((i-lo)*dim2span + (j-lo2)) * elemSize`.
- `m[i, j]` and `m[i][j]` indexing (read + write) — lower both to the same
  address computation.
- Cross-target byte-identical; add a `test_cross_multidim` and wire into all four
  suites.

## Notes

- Found alongside the case-range / paren-deref work while probing the language
  surface differentially against FPC. Not a miscompile — a missing feature.
