# bug: passing an array that is a member of an aggregate (record field / 2D-array row) as a var/const param segfaults

- **Type:** bug (codegen — address-of an aggregate-member array argument)
- **Status:** backlog
- **Track:** A
- **Opened:** 2026-06-25
- **Found-by:** Track B, Ed25519 (`lib/rtl/ed25519.pas`) — points modelled as
  `array[0..3] of TGf` (and as a record of 4 `TGf`) crashed; only 4 separate
  standalone `TGf` variables work.

## Symptom

Passing a fixed-array that lives **inside another aggregate** — a row of a 2D
array, or an array-typed record field — to a `var`/`const` array parameter
segfaults. A standalone array variable is fine.

```pascal
type TG = array[0..3] of Int64;
     TP = array[0..2] of TG;        { or: record a,b,c: TG; end; }
procedure Fill(var g: TG; v: Int64);
var i: Integer; begin for i := 0 to 3 do g[i] := v; end;
var p: TP;
begin
  Fill(p[0], 7);    { SEGFAULT — p[0] is an array that is an element of p }
end.
```

Both the `array[0..n] of TG` (row `p[0]`) and the `record … : TG` (field `p.a`)
forms crash. A plain `var g: TG; Fill(g, 7);` works.

## Likely cause

Forming the by-reference argument address for an array that is a sub-object of an
aggregate (element/field) is wrong — likely it passes a bad pointer (e.g. the
container's address, or a stack temp), so the callee writes/reads out of bounds.
Standalone array locals/globals take their address correctly.

## Impact / workaround

Hits any "array of vectors" / "record of vectors" layout — common in EC point
code (a point = 4 field elements). Workaround: keep each sub-array as a
**separate standalone variable** and pass them individually (e.g. a point becomes
4 `TGf` params, not one `array[0..3] of TGf`). `lib/rtl/ed25519.pas` does this —
see [[track-b-workarounds]].

## Acceptance

- `Fill(p[0], …)` / `Fill(p.a, …)` for an array element/field passes the correct
  address; no segfault; the element is updated in place.
- Regression test (2D array row + array-typed record field, var and const).

## Diagnosis (2026-06-25) — deeper than "address-of": element mis-sizing

Not (only) an address-of bug. The root is that **`array[..] of <named fixed-array
type>` mis-sizes its element**. Measured directly: for
`TG = array[0..1] of Int64; TP = array[0..1] of TG`, the outer-index stride
`PByte(@p[1]) - PByte(@p[0])` = **4**, not `SizeOf(TG)` = 16. So the whole `TP`
is laid out as if its element were a 4-byte Integer.

Cause: in the fixed-array type parse (parser.inc ~8903), the `of <ident>` element
handler only resolves a named **dynamic**-array alias (`FindArrayType` +
`ArrTypeIsDyn`). A named **fixed**-array alias (`TG`) is not handled there, so it
falls through to `elemTk := ParseTypeKind` (parser.inc ~8918), which resolves
`TG` via the scalar path and yields a bare base kind (→ ~4-byte Integer). The
array element size, total storage, and every index stride are then wrong.
`@p[1]` is garbage; `p[1][0]` (full double index) sometimes reads right only by
the multidim flat-offset path, while a single `p[1]` (a row) is wrong.

The record-field form (`record a,b,c: TG end`) is the same gap for an array-typed
record field.

### Why it is not a 5-line fix

- **Merging to a flat N-D array is wrong here.** `array[0..1] of TG` is not
  `array[0..1,0..1] of Int64` for *access*: FPC lets you take `p[0]` as a whole
  `TG` (and pass it to `var g: TG`). But the parser enforces an exact subscript
  count for `SymArrNDims >= 2` arrays (parser.inc:1412
  "wrong number of array subscripts"), so merging would reject the very `p[0]`
  the repro needs.
- The correct model is **array-of-aggregate-element**: the element is a sized
  block (like a record element, `RecSize`) whose own (base type, dims) are
  retained so `p[0]` is an lvalue of array type `TG`, `p[0][j]` indexes within
  it, and `p[0]` can be passed by-ref. The sym model today has `ElemType` +
  `ElemRecName` (record elements) but **no representation for an array element**.

So this needs: (1) parser — detect a named fixed-array alias element and record
its byte size + element (base type, dims); (2) sym/`AllocArray` — size the array
by that stride; (3) `IRLowerAddress`/AN_INDEX — stride by the aggregate size and
let a partial index yield the sub-array lvalue; (4) call-arg — pass `p[0]`/`p.a`
by-ref as a fixed `TG`. A type-system feature, scoped as such — not a codegen
patch. Track B workaround (split into standalone vars) stands until then.
