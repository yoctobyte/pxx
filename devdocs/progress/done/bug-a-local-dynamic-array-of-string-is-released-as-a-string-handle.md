---
track: A
prio: 45
type: bug
blocked-by: []
summary: "A local `array of string` is claimed by the x86-64 epilogue's SCALAR AnsiString arm — an array's TypeKind IS its element kind — so the array's DATA POINTER is handed to the string releaser and neither the elements nor the block are ever freed. Measured 560 bytes per call, linear: 200k calls leak 112 MB. Identical on pinned. The other four backends already carry the `not IsArray` guard; x86-64 was the outlier."
status: done
owner: claude-A
---

# A local dynamic array of string is released as if it were a string handle

- **Track A** (`compiler/symtab.inc`, `EmitManagedLocalCleanup`, x86-64 arm).
- Found 2026-08-21 while fixing the interface-container family, by running the
  cross-target build of that family's repro and noticing `dyn: 0` on aarch64 —
  which led to measuring the string case on every target, including x86-64.

## Measured

```pascal
procedure PArr;
var d: array of string; i: Integer;
begin
  SetLength(d, 8);
  for i := 0 to 7 do d[i] := 'element-padding-padding-padding-x';
end;
begin for k := 1 to 200000 do PArr; end.
```

| | peak RSS |
| --- | --- |
| `array of string` (above) | **112 512 kB** |
| same loop, `array of Integer` | 392 kB |
| same loop, a scalar `string` local | 392 kB |

Linear in the iteration count (20k → 11 560 kB, 200k → 112 512 kB), so it is a
leak and not a pool. **Identical on `pinned` (112 512 kB) and on HEAD before the
fix**, so it is not a recent regression — it has been there as long as the arm
ordering has.

## Cause

`EmitManagedLocalCleanup`'s arms are tried in order, and the SCALAR string arm
sat ABOVE the dynamic-array arm:

```pascal
else if Syms[i].TypeKind = tyAnsiString then      { <-- claimed array of string }
  ... mov rax,[rbp+off]; AnsiStrRelease
...
else if Syms[i].IsArray and (Syms[i].ArrLen = -1) then
  ... EmitDynArrayReleaseForSym(i)                { <-- never reached }
```

An array's `TypeKind` **is its element kind**, so `array of string` has
`TypeKind = tyAnsiString`, `IsArray = True`, `ArrLen = -1` and matched the first
arm. The array's DATA POINTER was then passed to the string releaser as though
it were a string handle. Nothing frees the elements, and nothing frees the block.

This is the same trap that
`bug-a-local-static-array-of-string-never-released-at-scope-exit` fixed for the
STATIC case — that fix added an arm *above* the scalar one, and the dynamic case
was left below it, so exactly half the bug was repaired.

## Fix

One guard: `(Syms[i].TypeKind = tyAnsiString) and not Syms[i].IsArray`. The other
four backends' epilogues already spell the arm that way; x86-64 was the outlier,
which is why this never showed up as a cross-target divergence report.

## Resolution 2026-08-21

Fixed as above, in the same change as the interface-container family
([[bug-a-a-local-array-of-interfaces-is-never-released-at-scope-exit]]), because
it is the same function and the same "an array's TypeKind is its element kind"
trap. Measured after: **392 kB**, flat — the same baseline as the non-leaking
shapes. Regression coverage: the `strarr:` round-trip line in
`test/test_interface_containers.pas` proves the elements still read back after
many calls (the leak itself is an RSS measurement, not something a test asserts).

Gate: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
