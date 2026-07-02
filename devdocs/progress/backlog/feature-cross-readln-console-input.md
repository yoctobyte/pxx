# Cross targets: readln (console input) unsupported — chess demo wall #3

- **Type:** feature (cross-backend builtin coverage)
- **Track:** A — `compiler/ir_codegen{386,_aarch64,_arm32,_riscv32}.inc`
- **Status:** backlog
- **Opened:** 2026-07-02

## Problem

`readln(line)` fails with `target <t>: builtin/special call not yet supported`
on i386/aarch64/arm32 (and the ESP targets have no stdin at all). With
stackless record generators done (2026-07-02), this is now the ONLY compile
error left between `examples/chess/chess.pas` (stackless variant) and the
i386/aarch64/arm32 cross targets: the REPL's `readln(line)` at chess.pas:897.

## Why it matters

- Blocks feature-demo-chess cross validation (perft selftest itself needs no
  input, but the whole program must compile).
- Any interactive cross-target program is walled the same way.

## Scope

- Lower READ/READLN of an AnsiString (and Integer, if cheap) on the 32-bit
  hosted targets via the existing PAL/syscall read path, mirroring x86-64.
- ESP bare can stay a clean error (no stdin) or read UART — Track A's call.

## Acceptance

- `readln(s: AnsiString)` echoes back correctly under qemu-user on
  i386/aarch64/arm32 (compare vs x86-64 oracle).
- Stackless chess variant compiles for i386/aarch64/arm32; perft selftest
  output identical to x86-64.

## Log
- 2026-07-02 — Filed by Track A while resolving
  feature-stackless-generator-record-locals.
