# `SetLength(a, x, y)` one-call multidim allocation not parsed

- **Type:** bug (parser) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30
- **Found by:** feature-dynarray-torture-test.

## Symptom

```pascal
var a: array of array of Integer;
begin SetLength(a, 2, 3); ... end.
```
→ `pascal26:2: error: unexpected token`. FPC allows `SetLength(arr, d1, d2, ...)`
to allocate a rectangular jagged array in one call (each extra dimension sizes the
sub-arrays). PXX's `SetLength` parser takes exactly `(lvalue, count)` and chokes on
the second size.

## Workaround (works today)

Per-row: `SetLength(a, 2); for i := 0 to 1 do SetLength(a[i], 3);` — the torture
test uses this. So the capability exists; only the one-call sugar is missing.

## Fix sketch

`ParseFactor`/statement `SetLength` branch (parser.inc ~8122): after the first
size expr, accept further `, <expr>` dimensions and lower to a per-dimension
init loop (or a runtime helper) that sizes the nested dynarrays. Rectangular only
(FPC semantics). Front-end + a small lowering.

## Acceptance

`SetLength(a, 2, 3)` allocates a 2×3 jagged array; `Length(a)=2`, `Length(a[i])=3`;
existing 2-arg `SetLength` unchanged; self-host byte-identical.
