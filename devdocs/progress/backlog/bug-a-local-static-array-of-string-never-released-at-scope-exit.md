---
summary: "a local `array[0..N] of string` never releases its element handles at scope exit — merely FILLING one in a called procedure leaks linearly (~60 MB per 1M calls)"
type: bug
track: A
prio: 55
---

# Local static array of AnsiString leaks every element at scope exit

- **Type:** bug — Track A (codegen / scope-exit managed cleanup)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** Track A, while ARC-testing the fix for
  `bug-a-static-array-of-managed-whole-assign-loses-data`. **Pre-existing and
  independent of that fix** — measured on both sides of it, identical numbers.

## Repro

```pascal
procedure Round1;
var a: array[0..2] of string;
    i: Integer;
begin
  for i := 0 to 2 do a[i] := 'val' + Chr(48 + i);
end;
var k: Integer;
begin
  for k := 1 to 400000 do Round1;
  writeln('array done');
end.
```

No assignment between arrays, no aliasing — just filling the array. RSS grows
linearly with the call count:

| iterations | max RSS |
| --- | --- |
| 100 000 | 6.3 MB |
| 400 000 | 24.8 MB |
| 1 600 000 | 100.0 MB |

Perfectly linear (~62 bytes/iteration, three string handles). The identical
procedure with a plain `s: string` local instead of the array is flat at
264 KB, so the scalar scope-exit release works and only the ARRAY case is
missing.

## Diagnosis sketch (unverified — measure before writing it into a fix)

The whole-array *assignment* path proves the ingredients exist:
`PXXDynArrayRetainImmediate` / `PXXArrayReleaseImmediate` walk a raw element
buffer with an explicit count and no header, which is exactly the shape a
static array needs. The suspicion is that the proc-epilogue managed-cleanup
walk (`ProcHasManagedLocalCleanup` and friends in `symtab.inc`) considers a
symbol's own TypeKind but not `IsArray` + `ElemType`, so an array-of-string
local is simply not on the cleanup list. Confirm with `PXXDBG` / the emitted
epilogue before changing anything.

## Severity

Silent, unbounded growth in any hot procedure holding a static string array —
the shape that reads as "the process is just big" rather than as a bug. Not
data loss, so ranked below the assignment bug it was found next to.

## Interaction with the assignment fix

`b := a` now retains the source's element handles and releases the
destination's old ones (`IRManagedArrayCopy`). That accounting is correct in
itself and adds no leak on top of this one — measured: an elementwise copy loop
and a whole-array `b := a` reach the identical 24.96 MB at 400 000 iterations.
Once THIS bug is fixed, the assignment path's retain/release balances exactly
as intended; no change is needed there.
