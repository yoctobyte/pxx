# PXX Documentation

`PXX` is a small self-hosting Object Pascal compiler for Linux x86-64. It emits
ELF executables directly — no assembler, no linker. The installed executable is
still `compiler/pascal26`.

These pages are deliberately short. PXX compiles a subset of Object Pascal, so
**for the language itself, use the [Free Pascal documentation](https://www.freepascal.org/docs.html)**.
These docs only record where PXX *differs* from FPC: what is not implemented,
what is not yet stable, and the dialect extras PXX adds.

## User docs

- [Command Line](cli.md) — how to invoke the compiler.
- [Dialect](dialect.md) — PXX-specific language features and switches.
- [Not Implemented](not-implemented.md) — FPC features PXX does not support.
- [Not Stable](not-stable.md) — implemented but unfinished; may change or break.

## Developer docs

Architecture, plans, roadmaps, audits, design notes, and historic handovers live
under [`developer/`](developer/README.md). Treat the source and the regression
suite (`make test`) as authoritative — implementation moves faster than docs.
