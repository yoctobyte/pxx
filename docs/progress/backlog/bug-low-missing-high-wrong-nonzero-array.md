# bug: Low() missing; High() wrong on non-zero-based arrays

- **Type:** bug (Track A — parser + codegen) — includes a silent miscompile
- **Status:** backlog
- **Found:** 2026-06-23, differential probe vs FPC
- **Severity:** medium-high (`High` returns a wrong value silently; `Low` absent)

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
