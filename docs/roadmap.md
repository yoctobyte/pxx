# PXX Target Roadmap

**Updated:** 2026-05-31

The immediate goal after the IR fixedpoint milestone is to turn the IR
backend into the default path, then systematically add CPU targets.
Self-replication fixedpoint must be confirmed at each stage before
moving to the next.

---

## Fixedpoint Rule

Every target milestone ends with the same gate:

```
compiler compiled by new target → recompiles itself → binary identical
```

This is non-negotiable. A target that cannot compile the compiler
correctly is not a shipped target.

---

## Phase 1 — Remove "Experimental" from IR ✅ (done 2026-05-29)

**Status:** Done. IR is the default backend; the compiler bootstraps through it.

The IR backend is self-consistent. Completed tasks:
- ✅ Full `make test` passes with IR as the backend (the former
  `test_op_overload.pas` IR red was cleared 2026-05-30).
- ✅ `--experimental-ir-codegen` is now a no-op alias (kept for compatibility).
- ✅ Legacy direct-emission `codegen.inc` retired from the active compiler and
  archived under `docs/historic/`.
- ✅ Fixedpoint confirmed: IR-compiled compiler → recompile → identical.

The active compiler now has one backend. `--experimental-ir-codegen` remains a
deprecated no-op for old scripts; `--legacy-codegen` was removed.

---

## Phase 2 — i386 Linux (32-bit Intel)

**Why first:** Same ISA family as x86-64. Instruction set is a subset.
Calling convention differences are well-documented. Easiest non-trivial
new target.

Key differences from x86-64:
- Pointer size: 4 bytes (`TARGET_PTR_SIZE = 4`)
- Calling convention: cdecl — arguments pushed right-to-left on stack,
  callee cleans nothing; `eax` returns integers; `st(0)` returns floats
- Registers: `eax`, `ebx`, `ecx`, `edx`, `esi`, `edi`, `ebp`, `esp`
  (no `r8`–`r15`)
- ELF: `EM_386` (machine type 3), 32-bit ELF header/sections
- Syscall: `int 0x80` ABI (different numbers than `syscall`)
- `Integer` stays 32-bit (matches x86-64 behavior — no change)
- `NativeInt`/`PtrInt` becomes 32-bit

Fixedpoint check: compile `compiler/compiler.pas` with `--target=i386`,
run result under QEMU (`qemu-i386`) or native i386, recompile, compare.

---

## Phase 3 — ARM64 / AArch64 Linux (Raspberry Pi 4+)

**Why next:** Raspberry Pi 4 and Pi 5 are AArch64. Huge installed base.
Good QEMU support for cross-development.

Key differences:
- ELF: `EM_AARCH64` (machine type 183), 64-bit ELF
- Pointer size: 8 bytes (same as x86-64)
- Calling convention: AAPCS64 — first 8 integer args in `x0`–`x7`,
  result in `x0`; frame pointer in `x29`, link register `x30`
- Instruction encoding: fixed 32-bit width, load/store architecture
  (no memory operands in arithmetic instructions)
- No `push`/`pop` — use `stp`/`ldp` pairs for frame save/restore
- PC-relative addressing for globals (`adrp` + `add`/`ldr`)

Fixedpoint check: compile under AArch64 Linux (native Pi or QEMU
`qemu-aarch64`), recompile, compare.

---

## Phase 4 — ARM32 Linux (Raspberry Pi 2/3, older Pi)

**When:** After AArch64 is stable. Shares conceptual work.

Key differences from AArch64:
- ELF: `EM_ARM` (machine type 40), 32-bit ELF
- Pointer size: 4 bytes
- Calling convention: AAPCS — first 4 args in `r0`–`r3`, result in
  `r0`; frame pointer `r11`, link register `r14`, stack pointer `r13`
- Thumb/Thumb-2 interworking optional (target plain ARM first)

Fixedpoint check: same pattern, under QEMU `qemu-arm` or native Pi.

---

## Phase 5 — Embedded / Bare Metal (ESP32 and similar)

**When:** After at least two Linux targets (i386 + one ARM) are stable.

This is a qualitatively different step. Linux targets share:
- ELF executable format with OS loader
- Syscall interface for I/O
- Virtual address space starting at a known base

Embedded targets have none of these. Required work:

### Binary output format
No ELF loader. Targets like ESP32 expect a raw binary or a
platform-specific image format. The `elfwriter.inc` output path needs a
parallel bare-metal binary writer.

### No syscalls
`writeln`/`readln` must map to a hardware abstraction (UART, SPI display,
etc.). Either:
- A thin HAL Pascal unit the user provides
- Or a built-in target-specific default (e.g. `writeln` → UART0 on ESP32)

Memory follows the same rule. Managed strings, dynamic arrays, classes, and
`GetMem` must work with the syscall-free internal heap described in
[`allocator-platform-design.md`](allocator-platform-design.md). Hosted targets
may add optional reserve/release/resize hooks; bare-metal ESP32 can initialize
the heap from linker-defined RAM regions, while an ESP32 RTOS profile can adapt
RTOS allocation services without changing language semantics.

### ESP32 specifics
- ESP32 original: Xtensa LX6 dual-core, 32-bit
- ESP32-C3/C6/H2: RISC-V (RV32IMC)
- ESP32-S2/S3: Xtensa LX7
- Each sub-variant is a distinct ISA; pick RISC-V (C3/C6) first —
  cleaner ISA, better tooling, no Xtensa license complexity

### RISC-V as the embedded entry point
RISC-V (RV32IMC for ESP32-C3) is worth targeting in its own right
beyond ESP32:
- Clean load/store RISC ISA, fixed 32-bit encoding (with compressed `C`
  extension optional)
- Calling convention: RISC-V integer ABI — `a0`–`a7` for args, `a0/a1`
  for return, `ra` link register, `sp` stack pointer
- Growing ecosystem (SiFive boards, QEMU `qemu-system-riscv32`)
- Same pointer-size work as i386

---

## Sub-32-bit Targets (AVR, 8051, etc.)

**When:** Not on the active roadmap. Theoretically possible.

The challenge is that Pascal `Integer` is 32-bit but these CPUs have
8-bit or 16-bit registers. The compiler must synthesize multi-word
arithmetic for every integer operation, which requires a different
codegen strategy (or a library of multi-word primitives).

Nothing architectural prevents this — the IR is abstract enough — but
the engineering effort is significant and the use case is niche.
Revisit after embedded Linux and RISC-V are stable.

---

## Cross-Compilation Model

PXX is already single-file and single-pass. Cross-compilation is
natural: the compiler binary runs on the host, emits bytes for the
target. No cross-linker, no sysroot.

For each new target, the `--target=` flag selects:
- ELF header machine type
- Pointer size and alignment
- Calling convention (arg passing, return registers)
- Instruction encoder (new `.inc` file, e.g. `codegen_i386.inc`,
  `codegen_aarch64.inc`)
- Syscall numbers and ABI

The IR layer above the instruction encoder is shared across all targets —
this is the core architectural benefit of the IR fixedpoint.

---

## Summary Table

| Phase | Target | ISA | Bits | ELF | Est. difficulty |
|-------|--------|-----|------|-----|-----------------|
| 1 | IR as default | x86-64 | 64 | Linux | Low |
| 2 | i386-linux | x86 | 32 | Linux | Low |
| 3 | aarch64-linux | ARM64 | 64 | Linux | Medium |
| 4 | arm-linux | ARM32 | 32 | Linux | Medium |
| 5 | riscv32 bare metal | RISC-V | 32 | None | High |
| 5 | ESP32-C3 | RISC-V | 32 | None | High |
| — | AVR/8051 | various | ≤16 | None | Very high |
