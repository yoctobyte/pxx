# feature: multidimensional typed-constant arrays

- **Type:** feature (Track A — parser / const initializers)
- **Status:** backlog
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
