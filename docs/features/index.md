---
title: Features
order: 30
---

# Features

PXX is a small native compiler with a direct frontend-to-ELF pipeline.

## Compiler

- Self-hosting Pascal compiler.
- Direct ELF executable output: no assembler or linker subprocess for normal
  Pascal programs.
- Alternate output modes for interop with other toolchains: `--emit-obj`
  writes a relocatable `.o` on any target; `--shared` writes an x86-64 `.so`
  (currently validated via the `.asm` assembly-source frontend).
- Byte-identical fixedpoint builds are part of the development gate.
- DWARF debug info with `-g` on Linux targets.

## Language

- Object Pascal subset with classes, interfaces, generics, overloads,
  operators, exceptions, RTTI, managed strings, dynamic arrays, and properties.
- Conditional compilation and a PXX identity symbol.
- Inline assembly and experimental alternate frontends are available, but should
  be treated as advanced or unstable surfaces.

## Libraries and tools

- Bundled runtime/library units under `lib/`.
- Example applications and demos under `examples/`.
- Optional Eliah IDE build from the checkout.
- Pinned stable compiler binary for ordinary use without FPC.

## Targets

- Native Linux x86-64.
- Cross output for Linux i386, aarch64, and arm32.
- ESP32-oriented riscv32 and xtensa output for embedded workflows.

## Current caution

PXX is experimental. Do not use generated programs for production, security
sensitive, safety sensitive, or public network-facing workloads.

## Next

- [Language](../language/)
- [Targets](../targets/)
- [Standard library](../library/)
