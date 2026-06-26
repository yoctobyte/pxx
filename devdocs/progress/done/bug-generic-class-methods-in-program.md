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

## Resolution (2026-06-25, Track A)

Fixed. A generic class-method impl (`procedure TBox.Meth` where TBox is a
template) is consumed by `ParseSubroutine` → `BufferGenericMethod` + Exit. The
program/unit 2-pass declaration prescan recorded it as a replayable DeclItem, so
pass 2 re-entered `ParseSubroutine` and buffered the SAME method a second time —
duplicate TemplateTokens + GenericMethods entries corrupted the specialization
stream ("expected name").

New flag `GenericMethodBuffered` (defs.inc): `ParseSubroutine` sets it when it
buffers a generic method and Exits; the four pass-1 drivers (ParseProgram +
ParseUnit, procedure/function and constructor/destructor) then skip recording the
DeclItem, so the method is buffered once and streamed by `specialize`. Generic
functions already avoided this by clearing PreScanPass around themselves; this is
the class-method analogue.

Front-end only — self-host byte-identical. Verified program generics (single +
multiple methods, function-result T, Integer + string specializations) and the
unit form (test_collections) unchanged. Test:
`test/test_generic_class_in_program.pas` (7 / hi) in `make test`; cross-checked
i386/aarch64/arm32.
