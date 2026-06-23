# bug: Low() missing; High() wrong on non-zero-based arrays

- **Type:** bug (Track A — parser + codegen) — includes a silent miscompile
- **Status:** done
- **Found:** 2026-06-23, differential probe vs FPC
- **Closed:** 2026-06-23
- **Severity:** medium-high (`High` returns a wrong value silently; `Low` absent)

## Resolution (2026-06-23)

Front-end only (parser fold), no codegen. Both defects use the array's stored
lower bound `Syms[].ConstVal` (set by AllocArray; 0 for open/dynamic/0-based):

1. `High(1-D static array)` now folds to `ConstVal + ArrLen - 1` (the upper
   index bound) instead of `ArrLen - 1` — fixes the silent miscompile for a
   non-zero lower bound (`array[5..9]` → 9, was 4). 0-based arrays unchanged
   (ConstVal=0). Open/dynamic `High` keeps the Length-based 0-based path.
2. `Low(array)` (the `tkLow` token added in feature-high-low-of-type) folds to
   `ConstVal` for a 1-D static array (`array[5..9]` → 5), else 0 (open/dynamic).

`for i := Low(a) to High(a)` idiom now correct. Verified byte-identical to FPC
for static (any bounds), 0-based, and dynamic arrays. N-D arrays keep existing
behavior (out of scope; ConstVal=0 for flattened N-D). Gate: `make test`
(self-host byte-identical, no reseed — front-end only) + FPC oracle.

## Two defects

### 1. `High(array)` returns the wrong value for a non-zero lower bound

`High` computes `count - 1` (a 0-based upper index) instead of the array's actual
upper index bound:

```pascal
var a: array[5..9] of integer; begin writeln(high(a)); end.   { fpc 9, pxx 4 }
var a: array[2..4] of integer; begin writeln(high(a)); end.   { fpc 4, pxx 2 }
```

For 0-based arrays it is correct by coincidence (`high(array[0..2])` = 2). This
is a **silent miscompile**: any code indexing `a[High(a)]` on a non-zero-based
array reads the wrong element / out of bounds.

### 2. `Low(array)` is unimplemented

```pascal
var a: array[5..9] of integer; begin writeln(low(a)); end.    { fpc 5, pxx: error: undefined variable }
```

Fails for static, open and (implied 0) dynamic arrays alike — `Low` is simply
not recognized.

### Consequence: the standard iteration idiom is broken

```pascal
var a: array[1..3] of integer; i: integer;
begin for i := low(a) to high(a) do a[i] := i; writeln(a[1], a[2], a[3]); end.
{ fpc: 123 ;  pxx: error: undefined variable (low) — and high would be wrong too }
```

## Expected

- `Low(a)` / `High(a)` return the array's declared index bounds (FPC semantics),
  for static (any bounds), open, and dynamic arrays.
- `High` must use the upper index bound, not `count - 1`, when the lower bound is
  non-zero.

## Relation

- `feature-high-low-of-type` covers `High/Low` applied to a *type/ordinal*; this
  is `High/Low` on an array *value* (a different path). `High(openarray)` and
  `High(dynarray)` already work and return correct 0-based values.
- Found via `tools/fpc_diff_probe.sh`.
