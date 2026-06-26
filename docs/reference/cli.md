---
title: Command line
order: 91
---

# Command line

The installed wrapper is normally called as:

```sh
pxx [options] source [output]
```

From a checkout, use:

```sh
./pxx [options] source [output]
```

The wrapper created by `install.sh` calls the pinned compiler and adds bundled
library roots. The underlying compiler executable is still named
`compiler/pascal26`.

## Source and output

With an output path, PXX writes the executable there and emits a matching map
file. Without an output path, it derives one from the source name and refuses to
overwrite the source.

## Options

| Option | Effect |
| --- | --- |
| `--target=ARCH` | Select `x86_64`, `i386`, `aarch64`, `arm32`, `riscv32`, or `xtensa`. |
| `--xtensa-abi=ABI` | Select the Xtensa call ABI variant. |
| `--emit-obj` | Emit a relocatable object instead of an executable. |
| `-g` | Emit DWARF debug information. |
| `--debug` | Print compiler tracing diagnostics. |
| `--dump-ir` | Print lowered IR while still emitting output. |
| `--dump-rtti` | Print generated RTTI tables while still emitting output. |
| `-dNAME` | Define a conditional compilation symbol. |
| `-uNAME` | Undefine a conditional compilation symbol, except `PXX`. |
| `-Mobjfpc` | Accept the Object Pascal compatibility mode marker. |
| `--strict-overload` | Require explicit `overload;` on overloaded routines. |
| `--permissive-overload` | Relax overload marker requirements. |
| `--threadsafe` | Use atomic refcounts for managed strings and arrays. |
| `--no-auto-var` | Disable auto-typed variable declarations. |
| `--no-lazy-var` | Disable inline/lazy variable declarations. |

## Examples

```sh
./pxx hello.pas hello
./pxx -g hello.pas hello
./pxx --target=aarch64 hello.pas hello.a64
./pxx -dDEBUG hello.pas hello
```

## Next

- [Install](../install/)
- [Targets](../targets/)
