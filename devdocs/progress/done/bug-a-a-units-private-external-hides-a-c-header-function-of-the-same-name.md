---
track: A
prio: 60
type: bug
blocked-by: []
summary: "A unit's IMPLEMENTATION-section `function f(...): T; external;` makes the same-named function from a later `uses <c header>` resolve as 'undefined variable (f)' in the using program/unit. Order-dependent: `uses ch, cu` compiles, `uses cu, ch` fails. Hit by 930d67d54a: scheduler.pas:628 declares heap_caps_get_largest_free_block privately, so museum_landkaart/async (uses scheduler, then idf) no longer compiles."
status: done
owner: ""
---

# A unit's private external hides a C header function of the same name

## Repro (riscv32 ESP object; probably every target)

ch.h:
```c
unsigned long largest(unsigned int caps);
```
cu.pas:
```pascal
unit cu;
interface
function UnitLargest: LongWord;
implementation
function largest(caps: LongWord): NativeUInt; external;
function UnitLargest: LongWord;
begin
  Result := largest(4);
end;
end.
```
cp.pas:
```pascal
program cp;
uses cu, ch;
function Get: LongWord; cdecl;
begin
  Result := largest(4) + UnitLargest;
end;
begin
end.
```
```
pascal26 --target=riscv32 --platform=esp --no-signals --emit-obj -I. -Fu. cp.pas cp.o
pascal26:5: error: undefined variable (largest)
```
With `uses ch, cu;` instead it compiles.

## Expected

An implementation-section declaration is private to its unit, so it should not
affect name lookup in units that use it. Even if it did leak, it names the same
C symbol with a compatible signature, so it should not end up as "undefined
variable".

## Real-world hit

lib/rtl/scheduler.pas:628 (930d67d54a, TrySpawnSized) declares
`heap_caps_get_largest_free_block` privately. museum_landkaart/async/src/lkapp.pas
has `uses platform, scheduler, ...;` and then `uses idf;`, and calls
heap_caps_get_largest_free_block from the header, which now fails. The app works
around it by putting `uses idf;` first. (espsys.pas:47 has the same private
declaration and would cause the same failure if an app uses espsys.)

## Log
- 2026-10-08: filed from museum_landkaart/async.
- 2026-10-08: fixed. The header prototype bound to the private row through the
  forceSystemExternal exact-name walk in ParseCSubroutine (cparser.inc), which
  scanned every proc with no visibility test (FindProc already answered -1).
  The walk now skips a row private to another unit. Makefile row
  impl_external_vs_header (red on the pinned compiler). Both orders compile;
  the object carries two `U largest` entries (one per row), which ld accepts.
