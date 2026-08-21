---
track: A
prio: 45
type: bug
blocked-by: []
summary: "A function whose RESULT is a dynamic array compiles natively and is REFUSED by all four cross backends — each epilogue errors on `Syms[retSymIdx].IsArray` with 'only ordinal/pointer/string function results supported yet'. One missing arm, four copies, three whole tests unbuildable on every non-x86-64 target."
status: backlog
owner: ""
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
