---
title: PXX — a self-hosting Pascal compiler
order: 0
---

# PXX (pascal26)

PXX is a **from-scratch**, self-hosting Pascal-dialect compiler. It is **its own
linker** — it emits final Linux ELF executables directly, with no external
assembler or linker in the path — and it compiles itself. Everything down to the
runtime and the ELF bytes is its own code, no toolchain dependencies.

> PXX is early experimental software. Do not use programs compiled by PXX for
> security-sensitive, safety-sensitive, financial, legal, medical, or public
> network-facing work.

**New here? → [Dive](./dive/)** — one page, five minutes, everything that
makes PXX worth a second look, with a working example and no need to browse
the rest of this documentation first.

## Highlights

- **Self-hosting.** The compiler is written in its own dialect and reproduces
  itself byte-for-byte.
- **Multiple targets.** x86-64 (native) plus i386, aarch64, and arm32 cross
  targets, and bare-metal ESP32 (xtensa / riscv32).
- **Multiple frontends.** Pascal is primary, but the same backend also compiles
  C, a Python-like dialect (Nil Python), and its own assembly-source frontend —
  see [Targets](./targets/).
- **Own RTL.** A from-scratch runtime and standard library with FPC-style naming.
- **Debug info.** `-g` emits DWARF (line tables, function/frame info, locals,
  types) on all four Linux targets — step, breakpoint, and backtrace under gdb.
- **Modern Pascal surface.** Classes, interfaces, generics, properties (including
  indexed/default), managed strings, dynamic arrays, exceptions, and more.
- **More than "just an executable."** Besides a normal linked binary, PXX can
  also emit a relocatable object (`--emit-obj`, `.o`) for linking with other
  toolchains, and — for its own assembly-source frontend — an ET_DYN shared
  library (`--shared`, `.so`). See the [command-line reference](./reference/cli.md).

## Where to go next

- [Dive](./dive/) — the fast, five-minute version of this whole project.
- [Install](./install/) — set up the pinned compiler and `pxx` wrapper.
- [Getting started](./getting-started/) — compile and run your first program.
- [Features](./features/) — what PXX can do today.
- [Language](./language/) — Pascal basics, the PXX dialect, and FPC
  compatibility notes.
- [Targets](./targets/) — native, cross, ESP32, and cross-language output.
- [Standard library](./library/) — the RTL and PCL units.
- [Examples](./examples/) — demo programs included in the checkout.
- [Reference](./reference/) — command line, configuration, limits, and glossary.

> These docs are published directly from the project's git repository. Found a
> mistake? The source lives in `docs/` — edits there flow to the site.
