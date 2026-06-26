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

An output path ending in `.o` also selects object-output mode, the same as
passing `--emit-obj`.

## Options

| Option | Effect |
| --- | --- |
| `--target=ARCH` | Select `x86_64`, `i386`, `aarch64`, `arm32`, `riscv32`, or `xtensa`. |
| `--xtensa-abi=call0\|windowed` | Select the Xtensa call ABI. |
| `--xtensa-cpu=lx6` | Use the older ESP32 LX6 software divide/mod profile. |
| `--xtensa-fpu` | Use Xtensa hardware single-precision float operations where supported. |
| `--esp-profile=bare` | Select the bare-metal ESP platform profile for `riscv32` or `xtensa`. |
| `--emit-obj` | Emit a relocatable object instead of an executable. Currently for ESP-style object flows. |
| `-g` | Emit DWARF debug information. |
| `--debug` | Print compiler tracing diagnostics. |
| `--dump-ir` | Print lowered IR while still emitting output. |
| `--dump-rtti` | Print generated RTTI tables while still emitting output. |
| `-dNAME` | Define a conditional compilation symbol. |
| `-uNAME` | Undefine a conditional compilation symbol, except `PXX`. |
| `-FuDIR` | Add a Pascal unit search root. |
| `-IDIR` | Add a C include directory and a Pascal unit search root. |
| `-Mobjfpc` | Accept the Object Pascal compatibility mode marker. |
| `--mimic-fpc` | Install the curated FPC compatibility define set for FPC-oriented libraries. |
| `--strict-overload` | Require explicit `overload;` on overloaded routines. |
| `--permissive-overload` | Relax overload marker requirements. |
| `--threadsafe` | Use atomic refcounts for managed strings and arrays. |
| `--no-auto-var` | Disable auto-typed variable declarations. |
| `--no-lazy-var` | Disable inline/lazy variable declarations. |

## Search paths

The wrapper created by `install.sh` already passes the bundled `lib/` roots.
Use `-Fu` for project-local units:

```sh
./pxx -Fusrc -Fulib/more app.pas app
```

Search roots are checked in flag order before the default library roots. That
lets a project override or add units deliberately without changing the checkout.

Use `-I` for C headers. It also feeds the Pascal unit search path, which is
useful for generated bindings that sit next to the imported header:

```sh
./pxx -Iinclude main.pas main
```

## Examples

```sh
./pxx hello.pas hello
./pxx -g hello.pas hello
./pxx --target=aarch64 hello.pas hello.a64
./pxx -dDEBUG hello.pas hello
./pxx -Fusrc -Iinclude app.pas app
./pxx --target=riscv32 --esp-profile=bare main.pas main.o
```

## Next

- [Install](../install/)
- [Targets](../targets/)
