---
title: PXX — a self-hosting Pascal compiler
order: 0
---

# PXX (pascal26)

PXX is a small, self-hosting Pascal-dialect compiler. It is **its own linker** —
it emits final Linux ELF executables directly, with no external assembler or
linker in the path — and it compiles itself.

## Highlights

- **Self-hosting.** The compiler is written in its own dialect and reproduces
  itself byte-for-byte.
- **Multiple targets.** x86-64 (native) plus i386, aarch64, and arm32 cross
  targets, and bare-metal ESP32 (xtensa / riscv32).
- **Own RTL.** A from-scratch runtime and standard library with FPC-style naming.
- **Debug info.** `-g` emits DWARF (line tables, function/frame info, locals,
  types) on all four Linux targets — step, breakpoint, and backtrace under gdb.
- **Modern Pascal surface.** Classes, interfaces, generics, properties (including
  indexed/default), managed strings, dynamic arrays, exceptions, and more.

## Where to go next

- [Getting started](./getting-started.md) — install and compile your first
  program.
- [Language reference](./language/) — types, classes, properties, and the rest
  of the dialect.
- [Standard library](./library/) — the RTL and PCL units.

> These docs are published directly from the project's git repository. Found a
> mistake? The source lives in `docs/site/` — edits there flow to the site.
