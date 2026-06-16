# Multidimensional fixed arrays

- **Type:** feature
- **Status:** done (2-D var-section)
- **Owner:** —
- **Opened:** 2026-06-16 (found via conformance feature-probing)
- **Closed:** 2026-06-16

## Done

2-D fixed arrays in `var` sections landed via the flatten-to-1-D design below:
both `m[i,j]` and `m[i][j]` fold into one linear `AN_INDEX` at parse time (dims in
parallel arrays `SymArr2*`), so the 1-D path handles codegen unchanged.
`test_cross_multidim` byte-identical on all 4 targets, matches FPC. The single
chokepoint was `ParseLValueAST` (both reads and writes of identifier indexing
route through it), so the "~6 sites" worry was overstated. Remaining follow-ups:
named array types / record-field / param 2-D, and 3-D+.

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

## Recommended design (flatten to 1D at parse time — zero codegen change)

Storage and indexing both reduce to the existing 1D array path, so no backend
work is needed (works on all four targets for free):

1. **Type parse** (`ParseVarSection` / typed-const / type-decl array branches):
   parse `array[lo1..hi1, lo2..hi2] of T` and `array[lo1..hi1] of array[lo2..hi2]
   of T`. Allocate a 1D array via `AllocArray(name, T, 0, span1*span2 - 1)` where
   spanK = hiK-loK+1. Record the dims in **parallel arrays keyed by sym** (do NOT
   add TSymbol fields — MAX_UFIELD landmine; mirror `SymDynDepth`):
   `SymArr2[sym]:Boolean`, `SymArr2Lo1/Span1/Lo2/Span2[sym]:Integer`.
2. **Index** `m[i,j]` and `m[i][j]`: build the flattened 1D index expression
   `(i - lo1) * span2 + (j - lo2)` and a single `AN_INDEX(m, flatExpr)`. Both
   forms collapse to the same thing (FPC treats them identically).

### Index-parse sites to touch (the spread-out risk — must be consistent)

All build `AN_INDEX` and currently parse exactly one `[expr]`; each needs to
accept a comma (`[i, j]`) and, when the base sym has `SymArr2`, emit the flattened
index. Centralise the flatten in one helper `BuildArr2Index(baseNode, sym)` called
from each:
- `parser.inc:1087` (primary lvalue suffix, in ParseLValueAST)
- `parser.inc:1932` (ParseFactor pointer-return-suffix)
- `parser.inc:2124` (ParseFactor general suffix)
- `parser.inc:2586` (alias-cast suffix)
- `parser.inc:7230` (a synthesised index target)
- the parenthesised-deref suffix added this cycle (ParseFactor tkLParen case)

For `m[i][j]` (nested AN_INDEX), detect a 2-level index on a `SymArr2` base and
fold the two into one flattened AN_INDEX at parse time (the inner `m[i]` row value
is not separately representable under flattening — error if used alone).

Build a `test_cross_multidim` (read+write, both syntaxes, non-zero los, Int64
elems) and wire into all four suites. Because flattening keeps it on the 1D path,
expect byte-identical across targets immediately.

## Notes

- Found alongside the case-range / paren-deref work while probing the language
  surface differentially against FPC. Not a miscompile — a missing feature.
- Deferred (2026-06-16) over implementing hastily: the ~6 index sites must change
  in lock-step, and an inconsistency would itself be a miscompile — exactly what
  the language-hardening goal is eliminating. The design above makes it a
  contained next task.
