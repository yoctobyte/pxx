# PXX Documentation

`PXX` is a small self-hosting Object Pascal compiler. It emits ELF executables
directly — no external assembler or linker. A program that imports no shared
objects is **static and syscall-only** (no libc, no loader); importing a shared
library (`external 'lib.so'`, x86-64) makes that binary dynamically linked. It
targets x86-64, i386, aarch64, arm32 (Linux) and riscv32/xtensa (embedded); see
[Targets](dialect/targets.md). The installed executable is still
`compiler/pascal26`.

These pages are deliberately short. PXX compiles a subset of Object Pascal, so
**for the language itself, use the [Free Pascal documentation](https://www.freepascal.org/docs.html)**.
These docs only record where PXX *differs* from FPC: what is not implemented,
what is not yet stable, and the dialect extras PXX adds.

## Public user docs

The website-oriented public docs live under [`site/`](site/index.md). Start
there for install, getting started, language, feature, target, library, and
reference pages.

## Legacy user notes

- [Command Line](cli.md) — how to invoke the compiler.
- [Dialect](dialect/README.md) — PXX-specific language features and switches
  (folder: targets, types, routines, classes, exceptions, generators, inline
  asm, directives).
- [Not Implemented](not-implemented.md) — FPC features PXX does not support.
- [Not Stable](not-stable.md) — implemented but unfinished; may change or break.

## Developer docs

Architecture, plans, roadmaps, audits, design notes, and historic handovers live
under [`developer/`](developer/README.md). Treat the source and the regression
suite (`make test`) as authoritative — implementation moves faster than docs.
