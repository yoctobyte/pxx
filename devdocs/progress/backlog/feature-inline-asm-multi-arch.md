# Inline assembly support for other architectures (i386, aarch64, arm32)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-21
- **Relation:** Extends inline assembly parser and instruction encoder in `compiler/asmenc.inc` to support i386, aarch64, and arm32 targets.

## Background

The compiler currently restricts inline assembly (`asm` blocks and `assembler` routines) to `x86-64` only, raising an error for all other architectures. This is because `compiler/asmenc.inc` parses x86-64 Intel-syntax and directly encodes it to x86-64 binary bytes.

## Goal

Extend the inline assembler to support:
1. **i386 (Intel 32-bit)**:
   - Reuse the Intel syntax parser.
   - Disable REX prefix emission.
   - Map registers to 32-bit equivalents (`eax`..`edi`, `esp`, `ebp`).
   - Support `int 0x80` for 32-bit Linux system calls.
2. **AArch64 & ARM32 (ARM 64-bit and 32-bit)**:
   - Implement an ARM assembly syntax parser and instruction encoder.
   - Support register names (`x0`..`x30`, `w0`..`w30`, `sp`, `lr`, `pc` for aarch64; `r0`..`r15` for arm32).
   - Support common instructions (`add`, `sub`, `mov`, `ldr`, `str`, `b`, `bl`, `svc` system calls).

## Implementation Steps

1. Update the architecture filter check in `AsmParseBody` in `compiler/asmenc.inc` to accept `TARGET_I386`, `TARGET_AARCH64`, and `TARGET_ARM32`.
2. Refactor parsing and encoding logic into target-specific sections or delegate to target encoders.
3. Write target-specific test cases under `test/` to verify correct instruction translation and local variable frame reference resolution.

## Log
- 2026-06-21 — Opened.
