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
