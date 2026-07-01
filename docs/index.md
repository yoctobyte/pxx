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

## What makes PXX different

Most "small" compilers still lean on an external toolchain somewhere — GNU `as`,
a system linker, libc. PXX doesn't. The lexer, parser, IR, every backend, the ELF
writer, the runtime library, and the GTK-based component library are all its own
code, hand-written for this project. FPC-compatible in dialect and naming, but
nothing is copied or ported from FPC, Borland, or anyone else.

It also proves itself on every change: the compiler is written in its own
dialect, and the development gate requires it to compile itself to a
byte-identical fixed point — build 2 must equal build 3, exactly, on every
supported target. A binary you build from this source is meant to be verified
against that source, not just trusted.

The minimalism shows up in the output too. The default build uses managed,
reference-counted strings, which pulls in enough runtime that a `hello world`
executable is a little over 31 KB. Opt into the older frozen-string ABI
(`-uPXX_MANAGED_STRING`, see [Types](./language/types.md#strings)) and the
same program links down to a 287-byte static ELF — no libc, no dynamic
section, just the syscalls it needs.

FPC compatibility is a means, not the goal — being able to lean on FPC's docs
and an existing Pascal ecosystem while building something independent. The
project exists mostly for the joy and the learning: for the maker who wants to
*understand* their tools, not just rent them.

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
