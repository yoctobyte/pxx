---
title: Dive
order: 5
---

# Dive

A single-page technical overview of PXX, verified against this checkout. The
rest of the documentation, linked at the end, covers each topic in depth.

## Overview

PXX is a from-scratch, self-hosting Pascal compiler.
It emits Linux ELF executables directly: no external assembler, no external
linker, and no libc dependency in the default build path. The lexer, parser,
intermediate representation, all six backends, the runtime library, and the
GTK-based component library are original code written for this project. The
dialect follows Free Pascal's naming and semantics where practical, but the
implementation is independent — nothing is copied or ported from FPC,
Borland, or elsewhere.

## Example

```pascal
program hello;
begin
  writeln('Hello, world!');
end.
```

```sh
./pxx hello.pas hello
./hello
```

```
Hello, world!
```

This produces a complete static ELF binary in one step, with no external
assembler, linker, or C compiler invoked during the build.

## Design points

- **Self-hosting.** The compiler is written in its own dialect. The
  development gate requires it to compile itself to a byte-identical fixed
  point — build 2 must equal build 3, exactly, on every self-hosting target.
- **Two string ABIs.** The default build uses managed, reference-counted
  strings; a `hello world` executable is approximately 31 KB. Compiling with
  `-uPXX_MANAGED_STRING` selects an older frozen-string ABI with no dynamic
  allocation for strings; the same program is a 287-byte static ELF. Both
  figures were verified on this checkout. See
  [Types](../language/types.md#strings).
- **Six targets, one compiler.** x86-64, i386, aarch64, and arm32 self-host
  byte-identical; xtensa and riscv32 target bare-metal ESP32 as emit-only
  backends. `--target=` selects the backend.
- **Multiple frontends.** The same backend also compiles a C frontend
  (tested against real-world C, including SQLite and Lua sources), a
  statically-typed Python-like dialect (Nil Python, `.npy`), and an
  assembly-source frontend.

<details markdown="1">
<summary>Compilation pipeline</summary>

Compilation proceeds through five stages, with no external tools invoked:

1. **Lexer** — source text to tokens. Dispatched by file extension: `.pas`
   Pascal, `.c` C, `.npy` Nil Python, `.bas` early BASIC.
2. **Parser** — tokens to an AST. Frontends share expression-parsing and
   type-checking where their semantics overlap.
3. **IR** — the AST lowers to a linear, target-agnostic intermediate
   representation.
4. **Codegen** — the IR lowers to target machine bytes. Six backends share
   one IR.
5. **ELF writer** — the compiler's own linker. Static output by default;
   `PT_DYNAMIC`/`DT_NEEDED`/GOT/PLT are added automatically when a C library
   is imported.

There is no optimization pass: no constant folding, no register allocation,
no dead-code elimination. Emitted code corresponds directly to the source.

See [Architecture](../reference/architecture.md) for the full pipeline.
</details>

<details markdown="1">
<summary>Current status</summary>

Established: the core Pascal language — classes, interfaces, generics,
exceptions, managed strings, dynamic arrays — compiles on all four Linux
self-host targets. A minimal class-based program was verified to build
cleanly on x86-64, i386, aarch64, and arm32 while writing this page. The C
and Nil Python frontends compile against real-world C headers and libraries.
DWARF debug information (`-g`) is available on all four Linux targets.

Known gaps: the two ESP32 targets (xtensa, riscv32) do not yet support
classes and are emit-only, not self-host, targets. There is no optimizing
pass. Integer arithmetic wraps without overflow checking. `private` and
`protected` are parsed but not access-enforced. Nil Python is limited to
four parameters per function and has no pointer syntax of its own. See
[Limits](../reference/limits.md) for the complete list.

PXX is early, experimental software. It should not be used for
security-sensitive, safety-sensitive, financial, legal, or medical work.
</details>

<details markdown="1">
<summary>Licensing</summary>

The repository currently grants no open-source or other license. Default
copyright applies: the code may be read, built, and run locally, but public
visibility on GitHub does not itself grant permission to copy, modify,
redistribute, or otherwise rely on it. This position may change in the
future. See
[`LICENSE.md`](https://github.com/yoctobyte/pxx/blob/master/LICENSE.md) in
the repository for the current terms.
</details>

## Further reading

- [Install](../install/) and [Getting started](../getting-started/)
- [Language reference](../language/)
- [Standard library](../library/)
- [Targets](../targets/)
- [Reference](../reference/)
