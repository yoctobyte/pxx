# bug: ArgStr(i, s) into a managed-string var rejected/broken on cross targets

- **Type:** bug (Track A — cross codegen / argv intrinsics)
- **Status:** done
- **Found:** 2026-06-23, full-sweep after the metaclass-construct work
- **Severity:** medium — blocks `test-i386` / `test-aarch64` / `test-arm32`
  (the cross gate is red on `test/test_arm32_arg_runtime.pas`). x86-64 is fine.

## Symptom

```
./compiler/pascal26 --target=i386 test/test_arm32_arg_runtime.pas /tmp/x
pascal26:13: error: target i386: ArgStr expects a string variable ()
```

Line 13 is `ArgStr(2, fixed)` where `fixed: string`. Same on aarch64 / arm32.

## Root cause

Scalar `string` is **managed (tyAnsiString) by default** now (pinned v26). So the
`ArgStr` destination lowers to `IR_LOAD_SYM` over a managed-handle slot.

- **x86-64** (`ir_codegen.inc`, `tkArgStr`) accepts the dest as `IR_LEA` *or*
  `IR_LOAD_SYM`, and branches on the slot type:
  `if Syms[symIdx].TypeKind = tyAnsiString then EmitArgvToStringManaged else EmitArgvToString`.
- **i386 / arm32 / aarch64** accept only `IR_LEA` and unconditionally call the
  **fixed-string** emitter (`EmitArgvToFixedString386` / `…Arm32` / inline A64).
  There is no managed-string path on the cross backends.

So today the cross backends hit `IRKind[valNode] <> IR_LEA` → the loud parse-time
error above. (Naively also accepting `IR_LOAD_SYM` is NOT a fix — it then runs the
fixed-string emitter against a managed slot and segfaults at the first read of the
string: verified `qemu: uncaught target signal 11`.)

## Fix

Give i386 / arm32 / aarch64 a managed-string ArgStr path mirroring x86-64's
`EmitArgvToStringManaged`: accept the `IR_LOAD_SYM` dest, and when
`Syms[symIdx].TypeKind = tyAnsiString` build a heap AnsiString from `argv[index]`
(length scan + alloc + copy + store handle) instead of the inline fixed buffer.
Each backend already has managed-string heap-assign helpers to build on.

## Acceptance

`make test-i386`, `make test-aarch64`, `make test-arm32` green; the three cross
runs of `test_arm32_arg_runtime` match the x86-64 oracle (`3 / <arg1> / <arg2>`).

## Not this

- `ParamStr` (managed) already works cross (it lowers via `IR_STORE_SYM`); this is
  specifically the `ArgStr(i, var)` statement form's fixed-only emitter.
- Pre-existing — confirmed on base @9a32b51 (before the metaclass commits), which
  touch no backend file. Surfaced by the argv-intrinsics test
  (`test_arm32_arg_runtime`, commit 7b20bef).

## Fix log

- 2026-06-24 — DONE. Gave i386 / arm32 / aarch64 a managed-string `ArgStr` path
  mirroring x86-64's `EmitArgvToStringManaged`. Each backend already had a managed
  argv builder used by `ParamStr` (`EmitArgvToAnsiString386` /
  `EmitArgvToAnsiStringArm32` / `EmitArgvToAnsiStringA64`, all: index reg in ->
  managed handle out) and a `LoadFile` publish sequence (release dst's old handle,
  store the new refcount-1 handle). The `ArgStr` statement handler now: when the
  dest lowers to `IR_LOAD_SYM` over a `tyAnsiString` slot, calls the managed
  builder and publishes; otherwise keeps the existing fixed/short inline-buffer
  emitter. All three `test_arm32_arg_runtime` cross runs now match the x86-64
  oracle (`2 / alpha / beta` for `… alpha beta`).
- NOTE: the cross gates (`make test-i386/aarch64/arm32`) are still red, but on
  *different, pre-existing* tests that were masked because `arg_runtime` failed
  first (the gate stops at the first error): `test_cross_frozen_strlen_deref`
  (i386/arm32 value mismatch vs x86-64 oracle) and `test_classref` (aarch64:
  "load through pointer of this type not yet supported"). Both reproduce on HEAD
  with the ArgStr change stashed → not caused here. Filed as
  `bug-cross-gate-masked-failures`.
