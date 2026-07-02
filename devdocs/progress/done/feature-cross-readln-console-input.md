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
- 2026-07-02 — Track A: DONE (i386/aarch64/arm32; riscv32 hosted still walled
  by bug-riscv32-hosted-writeln-hello-hangs, ESP bare has no stdin).
  Portable builtin helpers in builtinheap.pas (PXXReadLine/PXXReadDiscard/
  PXXReadVarStrM/PXXReadVarChar/PXXReadVarInt/PXXStdinEof — shared line
  buffer + Eof peek-byte pushback, mirroring the x86-64 asm semantics);
  IR_READLINE/IR_READ_VAR/IR_READ_DISCARD + bare-Eof builtin id 210 lowered
  to them in the 3 backends (x86-64 keeps its asm path untouched).
  test_readln.pas + test_eof_stdin.pas added to all 3 cross gates
  (output-identical vs x86-64 incl. the no-trailing-newline pushback case).
  RESULT: stackless chess compiles on i386/aarch64/arm32 and perft --selftest
  is BYTE-IDENTICAL to the x86-64 oracle on all three (CHECKSUM
  5554659317958071639, ALL OK).
