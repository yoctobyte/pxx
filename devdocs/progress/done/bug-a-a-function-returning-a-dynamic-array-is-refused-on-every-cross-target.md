---
track: A
prio: 45
type: bug
blocked-by: []
summary: "A function whose RESULT is a dynamic array compiles natively and is REFUSED by all four cross backends — each epilogue errors on `Syms[retSymIdx].IsArray` with 'only ordinal/pointer/string function results supported yet'. One missing arm, four copies, three whole tests unbuildable on every non-x86-64 target."
status: done
owner: claude-A
---

# A function returning a dynamic array is refused on every cross target

- **Track A** (`compiler/symtab.inc`, `EmitProcEpilog`'s four per-target result
  arms).
- Found 2026-08-21 by a 53-test cross differential over the dyn-array +
  interface family (see the baseline in
  [[bug-a-no-dyn-array-scope-exit-release-on-four-backends]]).

## Measured

```
$ ./compiler/pascal26 --target=i386 test/test_dynarray_torture.pas /tmp/x
pascal26:129: error: target i386: only ordinal/pointer/string function results
supported yet
```

Identical refusal, same cause, on all four:

| test | native | i386 | arm32 | aarch64 | riscv32 |
| --- | --- | --- | --- | --- | --- |
| `test_dynarray_torture` | ok | BUILDFAIL | BUILDFAIL | BUILDFAIL | BUILDFAIL |
| `test_length_dynarray_call` | ok | BUILDFAIL | BUILDFAIL | BUILDFAIL | BUILDFAIL |
| `test_setlength_dynarray_result` | ok | BUILDFAIL | BUILDFAIL | BUILDFAIL | BUILDFAIL |

The shape is just:

```pascal
function MakeArr(n: Integer): array of Integer;
var i: Integer;
begin
  SetLength(MakeArr, n);
  for i := 0 to n - 1 do MakeArr[i] := i + 1;
end;
```

## Cause

Each cross epilogue guards its result load with

```pascal
if Syms[retSymIdx].IsArray or (Syms[retSymIdx].Kind <> skLocal) or
   not (TypeIsOrdinal(...) or TypeIsFloat(...) or
        (Syms[retSymIdx].TypeKind in [tyAnsiString, tyPointer, tyClass])) then
  Error('target <t>: only ordinal/pointer/string function results supported yet');
```

`IsArray` is refused outright. But a DYNAMIC array result is not an aggregate —
it is a single pointer-sized handle, exactly like the `tyAnsiString` case
already allowed two lines down, and x86-64 returns it that way. A STATIC array
result is the genuinely unsupported case and must keep erroring.

So the fix is to let `IsArray and (ArrLen = -1)` through and load it at pointer
width — not through `EmitLoadVar*`, which sizes by `Syms[].TypeKind` and for an
array that is the ELEMENT kind (the truncation `EmitLoadVarA64` had until
2026-08-21: `array of Char` came back through a 4-byte `ldr w0` with the
handle's top half gone).

Ownership: the callee's Result handle transfers to the caller, which is why
every epilogue's managed-local cleanup already skips `retSymIdx`. That carve-out
is in place on all four, so this is the load, not the lifetime.

## Four copies of one epilogue, again

Same finding as [[bug-a-local-static-array-of-string-never-released-at-scope-exit]]
and [[bug-a-no-dyn-array-scope-exit-release-on-four-backends]]: five
hand-written epilogues, each missing a different arm.
[[refactor-a-the-missing-layer-between-frontends-and-backends]] is where that
stops recurring.

## Gate

The three tests above pass under `tools/run_target.sh` on i386 / arm32 /
aarch64 / riscv32 with the native output; a static-array result still errors;
self-host fixedpoint + `tools/gate.sh quick`.

## RESOLVED 2026-08-21

One arm per cross epilogue, placed before the `IsArray` refusal:

```pascal
else if Syms[retSymIdx].IsArray and (Syms[retSymIdx].ArrLen = -1) and
        (Syms[retSymIdx].Kind = skLocal) then
```

loading the handle at POINTER width by hand rather than through `EmitLoadVar*`
— which sizes by `TypeSize(Syms[].TypeKind)`, and an array's TypeKind is its
ELEMENT kind, so `array of Char` would have come back through a byte load with
most of the handle gone. (aarch64 uses `EmitLoadVarA64`, whose `ArrLen = -1`
arm was taught pointer width earlier the same day.)

Mirrors x86-64's arm exactly, comment and all — it already documented the same
reasoning: *"a narrow EmitLoadVar keyed on the element type would truncate (and
sign-extend) the pointer."*

### Static arrays were never the problem

Checked rather than assumed: a `function F: array[0..3] of Integer` builds and
runs correctly on all four cross targets both before and after, because it goes
through `ABIRetViaHiddenDestProc` long before the branch this ticket touched.
The `IsArray` refusal was catching only the dynamic case, which is the one that
did not need catching.

### Measured

| test | i386 | arm32 | aarch64 | riscv32 |
| --- | --- | --- | --- | --- |
| `test_dynarray_torture` | BUILDFAIL -> **ok** | same | same | same |
| `test_length_dynarray_call` | BUILDFAIL -> **ok** | same | same | same |
| `test_setlength_dynarray_result` | BUILDFAIL -> **ok** | same | same | same |
| `test_dynarray_result` | BUILDFAIL -> **ok** | same | same | same |

`test_dynarray_result` was not in the ticket's list — it turned up in the
differential, which is the argument for running one rather than checking the
three files the ticket names.

### Cross differential

53-test dyn-array + interface family, each target against the native answer,
versus the previous commit's baseline: **broke 0, fixed 16** (four tests x four
targets). The 18 disagreements that remain are all pre-existing interface-ARC
and ESP-platform issues untouched by this change.

### Gate

`tools/gate.sh quick` GREEN (self-host fixedpoint byte-identical).

## Log
- 2026-08-21 — resolved, commit 481c397c6.
