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
  writes a relocatable `.o` on x86-64, i386, aarch64, arm32, riscv32 and
  xtensa; `--shared` writes a `.so` on x86-64 only. See
  [Targets](../targets/index.md#what-each-target-supports).
- Zero-dependency binaries by default: no libc, no `DT_NEEDED`, only Linux
  kernel syscalls at runtime — for every frontend, not just C. Linking a system
  shared library is opt-in and the only thing that adds a dependency; the
  alternative is compiling that library's source in, which keeps the binary
  self-contained.
- Cross-language imports with no wrapper layer: frontends share one backend,
  symbol table, and import resolver. A Pascal `uses` can resolve a C header,
  and a Nil Python `import` can resolve a Pascal unit or a C header, through the
  same chain, with no FFI blocks, IDL or generated bindings. Pascal does not
  import Nil Python modules, and C imports only C headers. See [Cross languages](../targets/cross-languages.md).
- Byte-identical fixedpoint builds are part of the development gate: the
  compiler rebuilds itself and the two binaries must match to the byte, at the
  default optimisation level. This is the compiler reproducing **its own**
  output — a different claim from the output parity against gcc- and FPC-built
  references described in [Compatibility status](../reference/status.md).
- DWARF debug info with `-g` on x86-64, i386, aarch64 and arm32 (not on
  riscv32 or wasm32).
- It builds a bootable system: PXX compiles a 19-applet BusyBox userland,
  including the `ash` shell, whose output matches a GCC build of the same
  sources across a differential case list. That userland is linked with no C
  library other than PXX's own, and `tools/mkminimal.sh` packages it, a stock
  Linux kernel and the compiler itself into one BIOS+EFI ISO. See
  [A minimal Linux system](../examples/minimal-linux-system.md).

## Language

- Object Pascal dialect with classes, interfaces, generics, overloads,
  operators, exceptions, RTTI, managed strings, dynamic arrays, and properties
  (including indexed and default).
- Interfaces in both models: COM (reference-counted, the default) and CORBA
  (unmanaged, `{$interfaces corba}`).
- Advanced records (methods, constructors, `class operator` overloads),
  metaclasses (`class of`), and class properties / class vars.
- Opt-in FPC-parity runtime checks per region: range (`{$R+}`),
  overflow (`{$Q+}`), and IO (`{$I+}`); plus opt-in strictness flags
  (`--strict-visibility`, `--strict-case`, …). Lax by default.
- Conditional compilation and a PXX identity symbol.
- Concurrency on two axes: a single-thread cooperative coroutine scheduler, plus
  real OS threads (`TThread`) and a data-parallel `parallel for` loop over a
  libc-free worker pool (build threaded code with `--threadsafe`).
- Inline assembly and an assembly-source (`.asm`) frontend are available, but
  should be treated as advanced or unstable surfaces.
- Alternate high-level frontends: a [C frontend](../targets/c-frontend.md)
  (C99-class, passes all 220 programs of the c-testsuite conformance battery
  with pin v424 on x86-64, and compiles real programs such as SQLite, Lua,
  zlib, cJSON and QuickJS) and
  [Nil Python](../targets/nil-python.md), a statically-typed Python-shaped
  dialect. Both are mainline, gated frontends, not experiments — see
  [compatibility status](../reference/status.md).

## Libraries and tools

- Bundled runtime/library units under `lib/`.
- Example applications and demos under `examples/`.
- Optional Eliah IDE build from the checkout.
- Pinned stable compiler binary for ordinary use without FPC.

## Targets

- Native Linux x86-64.
- Cross output for Linux i386, aarch64, arm32 and riscv32, and for wasm32
  (WebAssembly, run with wasmtime).
- ESP32 output (riscv32 and xtensa) as an ESP-IDF component or a bare-metal
  image. See [Targets](../targets/index.md) for what each one supports.

## Current caution

PXX is experimental. Do not use generated programs for production, security
sensitive, safety sensitive, or public network-facing workloads.

## Next

- [Language](../language/)
- [Targets](../targets/)
- [Standard library](../library/)
