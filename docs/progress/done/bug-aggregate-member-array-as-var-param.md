# bug: passing an array that is a member of an aggregate (record field / 2D-array row) as a var/const param segfaults

- **Type:** bug (codegen — address-of an aggregate-member array argument)
- **Status:** DONE (2026-06-25, Track A — commits 3a19116 + ef2ee46)
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

## Resolution (2026-06-25, Track A — front-end only, self-host byte-identical)

Fixed in two parser commits. The earlier "why it is not a 5-line fix" worry —
that merging to a flat N-D array would reject the partial `p[0]` — was wrong:
the exact-subscript-count check (parser.inc:1412/1426) only fires for the comma
(`m[i,j]`) and consecutive-bracket (`m[i][j]`) forms. A lone leading subscript
`m[i]` falls to the plain `else` branch and is accepted — so merge + handle the
partial there.

**1. `3a19116` — `array[..] of <named FIXED-array type>` merges to multidim.**
The element-mis-sizing root: `of TG` (TG a named fixed-array type) fell through
to `ParseTypeKind`, which dropped TG's dimension and collapsed the element to its
bare base (stride 8→4). Now a named fixed-array element is merged into the outer
dim list exactly like the anonymous-nested (`array[a] of array[b] of T`) and
true-2D (`array[a,b] of T`) forms — at all three sites: named array-type
definition (~10516), inline var (~8903), record field (~10087/10313). So
`array[0..2] of TG` and `record a,b: TG end` become real flattened N-D layouts;
`p[i][j]` / `r.a[i]` and index-0 var-params (`Fill(p[0], …)`, `Fill(r.a, …)`)
are correct.

**2. `ef2ee46` — a lone leading subscript of an N-D fixed array selects a row.**
`p[1]` (partial) was lowered with element stride → address `base + i*elemSize`
instead of `base + i*rowSize`, so `Fill(pts[i], …)` (variable `i`) aliased wrong
bytes. This was **pre-existing for true-2D arrays too**, not specific to the
named-type form. `ParseLValueAST` now scales a lone subscript to the row's
first-element flat index `(i-lo0)*span1*..*span_{n-1}` (BuildPartialNDRowIndex),
so the ordinary element-stride AN_INDEX yields the row base address — which is
what a `var`/`const` array param needs. No sym-model "array element" type, no
codegen change. The callee handles the by-ref row via the existing fixed-array
`var` param ABI (slot holds &row, derefs and indexes).

Verified: `array[0..2] of TG` and `record …: TG` var-params with both constant
and variable row index; `pts[i]` (Ed25519 point pattern) writes the right row;
true-2D `array[0..2,0..3]` row var-param; nested full indexing and 3-D
(`a[i][j][k]`, `a[i,j,k]`) unchanged; `make test` green; bootstrap byte-identical.

Track B can now model EC points as `array[0..n] of TGf` / `record …: TGf` and
drop the split-into-standalone-vars workaround once it rebuilds on the next pin.
