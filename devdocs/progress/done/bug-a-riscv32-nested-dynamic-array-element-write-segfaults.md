---
summary: "riscv32: writing an element of a NESTED dynamic array (`a[i][j] := x`) segfaults. Pre-existing on pinned; the flat case and all other targets are fine."
type: bug
track: A
prio: 50
status: done
owner: claude-AN
---

# riscv32: an element write through a NESTED dynamic array segfaults

- **Type:** bug — Track A (riscv32 backend). Files: `compiler/ir_codegen_riscv32.inc`.
- **Found:** 2026-08-06, cross-checking every target while fixing
  `bug-a-x86-64-dynarray-assignment-copies-instead-of-aliasing`.
- **Pre-existing:** reproduces identically on `stable_linux_amd64/default/pinned`,
  so it is not from that fix.

## Repro

```pascal
program nest;
var a, b: array of array of Integer;
    i: Integer;
begin
  SetLength(a, 2);
  for i := 0 to 1 do begin SetLength(a[i], 2); a[i][0] := i; a[i][1] := i * 10; end;
  b := a;
  b[0][0] := 77;
  writeln('nested write thru b: a[0][0]=', a[0][0], ' b[0][0]=', b[0][0]);
end.
```

```
$ ./compiler/pascal26 -dPXX_MANAGED_STRING --target=riscv32 nest.pas n_rv
$ tools/run_target.sh riscv32 n_rv
Segmentation fault (core dumped)     # exit 139, no output at all
```

Nothing prints, so it dies before the first `writeln` — i.e. in the
`SetLength(a[i], ...)` / nested-element-write sequence, not in output.

## Boundary, measured

| case | riscv32 |
| --- | --- |
| `writeln(42)` — riscv32 runs at all | ✅ |
| FLAT dynamic array: `b := a; b[0] := 77` | ✅ correct, and matches FPC |
| **NESTED: `array of array of Integer`, element write** | **SIGSEGV** |
| the same nested program on i386 / arm32 / aarch64 / x86-64 | ✅ all four correct |

So this is riscv32-specific and depth-specific. The flat case working rules out
the store arm and the runner; the other four targets working on the identical
program rules out the shared IR.

## Where to look first

`IR_DYNUNIQUE` in `compiler/ir_codegen_riscv32.inc` is the nested-level
data-pointer load, and its comment records that it "was an 'unsupported node'
error on riscv32" before being added — i.e. riscv32 got this arm late, mirroring
arm32. `IR_SETLEN_DYN` on a nested slot address is the other candidate. Note the
riscv32 arm was simplified along with every other backend when the nested
copy-on-write was removed, and the crash predates and survives that change
identically, so it is not the deref itself.

Worth checking whether `PXXDynSetLen`'s ESP-lean body is what riscv32 links (see
`compiler/builtin/builtinheap.pas` — riscv32 is also the C3 target and takes some
ESP-shaped paths), because a lean SetLen that skips the managed/sub-array retain
would explain a nested handle being wrong while flat is fine.

## Gate
The repro above running clean under `tools/run_target.sh riscv32` and matching an
FPC build's output, plus `test/test_dynarray_whole_assign.pas` — whose
`AliasesNested` case is exactly this shape — extended to the riscv32 differential
job once it passes. (It is deliberately NOT wired into the riscv32 job today,
because it would land red on this bug rather than on anything the aliasing fix
did.)

## 2026-08-07 — FIXED

### The crash was not where the ticket looked, and the first symptom was earlier

`IR_DYNUNIQUE` and `PXXDynSetLen`'s ESP-lean body were both innocent. Bisecting
the repro moved the failure *up*, before any element write:

```pascal
var a: array of array of Integer;
SetLength(a, 2);
writeln(Length(a));    { riscv32: 0 — x86-64/i386/arm32/aarch64: 2 }
```

The outer `SetLength` silently did nothing. Everything after it — `SetLength(a[i], …)`,
the element writes, `Length(a[0])` — was then operating through a nil handle,
which is where the SIGSEGV came from. `array of AnsiString` and
`array of record` (managed elements, depth 1) are fine, so it is depth, not
element management.

### Cause

`SetLength` on a depth >= 2 array lowers to `IR_SETLEN_DYN`, whose riscv32 arm
emits its slot-address operand as an ordinary node under `InLValueWrite`. That
operand is an `IR_LEA` of the array symbol — and riscv32's `IR_LEA` **always**
dereferences a dynamic array's slot, in read and write position alike. So
`PXXDynSetLen` was handed the array's CURRENT handle instead of `&slot`; for a
fresh array that is nil, and its first line is

```pascal
  if (arrSlot = nil) or (desc = nil) then Exit;
```

— a silent no-op. The FLAT `SetLength(a, n)` path never comes through `IR_LEA`
(the `-102` intrinsic computes the slot address with `EmitSlotAddrRISCV32`
directly), which is exactly why flat worked and nested did not.

arm32 carried the identical bug and fixed it in `bug-nested-dynarray-cross-segfault`
by gating its `IR_LEA` dynamic-array deref on `InLValueWrite`. **That fix does
not transplant.** Tried it first and measured the result: on riscv32 an indexed
WRITE (`a[3] := 42`) also arrives at `IR_LEA` with `InLValueWrite` set and needs
the data pointer, so gating it broke every element store on a flat array —
`d2.pas` printed `len=8` and then segfaulted on `a[3] := 42`. Reverted.

### Fix

`IR_SETLEN_DYN` computes the slot address itself when its target is a plain
dyn-array symbol — `EmitSlotAddrRISCV32`, plus the one deref a by-ref `var`
param needs — and falls back to emitting the node otherwise. Same shape the flat
`-102` path uses two thousand lines above, and it leaves `IR_LEA`'s
read/write behaviour untouched.

### Measured

| case | before | after |
| --- | --- | --- |
| ticket's `nest.pas` repro | SIGSEGV, no output | `a[0][0]=77 b[0][0]=77` — matches an **FPC** build of the same file |
| `SetLength(a, 2)` on `array of array of Integer` | `Length(a) = 0` | `2` |
| `test/test_dynarray_whole_assign.pas` on riscv32 | SIGSEGV | byte-identical to the x86-64 build |
| `test/test_nested_dynarray_setlen.pas` on riscv32 | (skipped) | byte-identical to the x86-64 build |
| flat dynamic arrays, managed-element arrays | ok | ok |

### Gate + coverage

`make test-riscv32` GREEN in full, `tools/gate.sh quick` GREEN, self-host
byte-identical. Two tests un-skipped / newly wired into the riscv32 differential
job, which is what the ticket's Gate line asked for:

- `test/test_nested_dynarray_setlen.pas` — was marked `# SKIP … backend feature
  gap`; the "feature gap" was this bug.
- `test/test_dynarray_whole_assign.pas` — its `AliasesNested` case is exactly
  this shape, deliberately left unwired because it would have landed red here.

## Log
- 2026-08-07 — resolved, commit abda21677.
