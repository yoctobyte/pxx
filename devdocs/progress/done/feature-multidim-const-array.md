# feature: multidimensional typed-constant arrays

- **Type:** feature (Track A — parser / const initializers)
- **Status:** DONE 2026-06-23 (commit e0fe418)

## Resolution (2026-06-23)

`const M: array[0..1,0..1] of integer = ((1,2),(3,4))` parses for global +
routine-local consts; 2-D / 3-D / non-zero-based verified (`1 2 3 4` /
`10 30 40 60` / `1 4 5 8` / local `7 8 9 10`). The const-array path adopted the
var-section ND handling: comma-separated dims flatten to a 1-D row-major store
with `SymArrNDims`/`DimLo`/`DimSpan` set (so `M[i,j]` reads via
`BuildFlatNDIndex`). The nested `((..),(..))` initializer is consumed by a
paren-depth walk and filled row-major; the flat-index writes lower identically
to the single-flat-index reads `BuildFlatNDIndex` already emits. Front-end only;
self-host byte-identical; `make test` green. **Not pinned** (no Track B request).

Test: `test/test_multidim_const_array.pas`.

---

(original below)

- **Status (orig):** backlog
- **Found:** 2026-06-23, differential sweep vs FPC
- **Severity:** low-medium (common for static lookup tables; a 1-D const +
  manual indexing is the workaround)

## Gap

A multidimensional **typed constant** array does not parse:

```pascal
const M: array[0..1,0..1] of integer = ((1,2),(3,4));
```

```
Expected: ], but got: (Kind: 80 = tkComma)
```

Two missing pieces:
1. **Type bounds.** `ParseConstSection`'s typed-const array path
   (`if CurTok.Kind = tkArray` → `cLo := ConstEval; '..'; cHi := ConstEval;
   Expect(']')`) handles only a single `[lo..hi]`; the `,` of a second dimension
   trips the `]` expectation. (The var-section/`AllocArray` path already supports
   `array[a,b]` via `SymArrNDims`/flattening — this path needs the same.)
2. **Nested initializer.** The const-array initializer loop is a flat
   `repeat ParseInitVal until not Eat(',')`, so the nested `((1,2),(3,4))` form
   is unhandled. It needs to walk the parenthesised rows and flatten them into
   the pending-init element list in the same row-major order the multidim var
   layout uses (`BuildFlatNDIndex`).

Works today: 1-D typed const arrays (`const A: array[0..2] of integer =
(10,20,30)`), and multidim **var** arrays with `[i,j]` indexing. Only the
multidim *const initializer* combination is missing.

## Workaround

Declare a 1-D const sized `rows*cols` and index `M[r*cols + c]`, or use a `var`
array filled at startup.

## Repro

`const M: array[0..1,0..1] of integer = ((1,2),(3,4)); begin writeln(M[0,0]); end.`
(FPC prints the table; pxx fails at the type bounds.)
