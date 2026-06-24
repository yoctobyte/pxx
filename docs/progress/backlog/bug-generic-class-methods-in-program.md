# Generic class METHOD bodies break in a program (work in a unit)

- **Type:** bug (parser / generic prescan)
- **Status:** backlog (Track A)
- **Owner:** —
- **Opened:** 2026-06-24

## Summary

Generic classes ARE supported — but only when the template + its method bodies
live in a **unit** (interface/implementation), as `lib/rtl/collections.pas`
(`generic TList<T>`) does; `test/test_collections.pas` specializes and uses it.

In a **program**, a generic template whose methods have implementations fails:

```pascal
program g;
type generic TBox<T> = class
  Value: T;
  procedure SetIt(v: T);
end;
procedure TBox.SetIt(v: T); begin Self.Value := v; end;   { method impl }
type TIntBox = specialize TBox<Integer>;
var b: TIntBox;
begin b := TIntBox.Create; b.SetIt(42); writeln(b.Value); end.
```
→ `error: expected name` (reported at the template's first field line).

## Narrowing

- template + field, no methods, + specialize → OK (`b.Value` works).
- template + method DECLARATION + specialize (no impl) → OK.
- template + method IMPLEMENTATION (`procedure TBox.SetIt`) in a program → FAILS.
- same template + impls in a UNIT (collections.pas) → OK.

## Suspected cause

`ParseProgram` runs a 2-pass declaration prescan; a generic class method impl
(`procedure TBox.SetIt`) goes through `ParseSubroutine` → `BufferGenericMethod`
in BOTH passes (generic FUNCTIONS clear `PreScanPass` around themselves —
parser.inc ~13844 — but generic class-method impls do not). Double-buffering /
double-streaming corrupts the specialization token stream. `ParseUnit` already
guards this (see the "clear PreScanPass around generic/operator + in ParseUnit"
landmine), which is why the unit form works.

## Fix direction

Guard `BufferGenericMethod` (and the specialize streaming it triggers) so a
generic class method impl is buffered/streamed exactly once across the program's
two prescan passes — mirror the generic-function `PreScanPass` handling.

## Done when

- The program repro compiles and `b.SetIt(42)` then `b.Value` = 42.
- Regression test under `make test`.
- Self-host fixedpoint byte-identical.
