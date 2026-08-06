---
summary: "riscv32: writing an element of a NESTED dynamic array (`a[i][j] := x`) segfaults. Pre-existing on pinned; the flat case and all other targets are fine."
type: bug
track: A
prio: 50
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
