# A function returning a record with float fields loses the values (returns 0)

- **Type:** bug (codegen — record-return ABI for float-field structs)
- **Track:** A — `compiler/**`
- **Status:** backlog (HIGH — silent wrong values)
- **Owner:** — (Track A)
- **Opened:** 2026-06-25
- **Found-by:** while fixing [[bug-plain-byvalue-record-param-temp]] — the
  `Vec3 = record x,y,z: Double end` chain returns all-zero, independent of the
  by-value-param-temp parse issue (which is fixed). This is the real reason the
  raytracer's vector math would be wrong without help.

## Symptom

A function whose result is a record with **floating-point fields** returns zeros;
the field stores to the result var (`Result.x := …` or `FuncName.x := …`) do not
land. Even reading the result field back **inside** the function yields 0. A
record with **integer** fields of the same size returns correctly.

```pascal
type R3d = record a, b, c: Double end;     { 24 bytes }
function MkD(x: Double): R3d;
begin
  MkD.a := x;
  writeln(MkD.a:0:1);     { prints 0.0 — the store did not land }
end;
```

## Isolation (all on x86-64, reproduces on stable v62)

| record | field type | size | result correct? |
| --- | --- | --- | --- |
| 1 field | Double | 8B | **OK** |
| 2 fields | Double | 16B | **OK** |
| 3 fields | Double | 24B | **zeros** |
| 3 fields | Single | 12B | **zeros** |
| 3 fields | Int64 | 24B | OK |
| 3 fields | LongInt | 12B | OK |

- Integer-field records of any size return correctly — so the generic record
  return / hidden-aggregate path is fine.
- A **local** float record var (not a function result) stores/loads correctly;
  only the **function-result** float record breaks.
- 1–2 float fields work; **3 float fields** fail at both 12B (3×Single) and 24B
  (3×Double). So it is not a pure size threshold — it correlates with an eightbyte
  that packs multiple float fields and/or a 3rd float field. Smells like the
  SysV-AMD64 SSE-class return classification for float-field structs (eightbyte
  SSE packing / the >16B MEMORY-class result var) being mishandled specifically
  when float fields are involved.

## Repro

```pascal
program p;
type R3d = record a, b, c: Double end;
function Mk(x,y,z: Double): R3d;
begin Mk.a:=x; Mk.b:=y; Mk.c:=z; end;
var r: R3d;
begin r := Mk(1,2,3); writeln(r.a:0:1,' ',r.b:0:1,' ',r.c:0:1); end.
{ prints 0.0 0.0 0.0 — want 1.0 2.0 3.0 }
```

## Impact

Any function returning a vector/color/matrix record of floats >2 fields (graphics,
physics, the raytracer `Vec3`/`Vec4`). Silent — no error, just zeroed results.

## Done when

- `Mk(1,2,3)` for `record a,b,c: Double` returns `(1,2,3)`; same for 3×Single and
  larger float records; integer records stay correct.
- The `Vec3` `VAdd(VScale(V(1,1,1),0.5), V(2,2,2))` chain gives `z.x = 2.5`.
- `examples/raytracer` renders correctly with plain by-value (or const) Vec
  params.
- Regression test under `make test` (float-field record results, several sizes);
  self-host fixedpoint byte-identical.
