# `Insert` / `Delete` intrinsics for dynamic arrays

- **Type:** feature (compiler intrinsic) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30
- **Found by:** feature-dynarray-torture-test.
- **Relation:** the dynarray siblings of the string `Insert`/`Delete` (done) and
  [[feature-copy-intrinsic]] (the same generic-over-element-type shape).

## Symptom

```pascal
var a: array of Integer;
begin SetLength(a,4); ...; Delete(a, 1, 2); end.   { -> error }
begin ...; Insert(99, a, 1); end.                  { -> error }
```
→ `Delete: string argument expected (dynamic-array Delete not yet supported)` /
`Insert: string destination expected (dynamic-array Insert not yet supported)`.
String `Insert`/`Delete` work; the dynamic-array forms are explicitly rejected.

## Scope

- `Delete(arr, index, count)` — remove `count` elements at `index`, shift down,
  shrink. Element-type aware (managed elements released).
- `Insert(value, arr, index)` — grow by 1, shift up, store `value` at `index`.
  (FPC also has `Insert(srcArr, arr, index)` to splice an array — phase 2.)

## Fix sketch

Generic over element type (like Copy) — needs a per-element-size lowering or a
runtime helper taking element size + a managed-field descriptor. The string
versions in builtin.pas are the template; the dynarray versions must handle
arbitrary element size + managed-element release on Delete.

## Acceptance

`Delete`/`Insert` on a dynamic array shift + resize correctly (with managed
elements released/retained as appropriate); string forms unchanged; regression
tests; self-host byte-identical.
