---
title: Getting started
order: 10
---

# Getting started

## Install

A fresh checkout already ships a working compiler (the pinned stable binary), so
the fastest path needs no toolchain at all:

```sh
git clone <repo> pxx && cd pxx
./install.sh
```

`install.sh` verifies the compiler, drops a ready-to-use `./pxx` wrapper in the
project root (compiler + all library roots on the search path), and offers — all
opt-in — to put `pxx` on your PATH, fetch external libraries (Synapse), install
the ESP32 toolchain, build the Eliah IDE, and launch the demos. Run `./demos.sh`
any time to build and run the example apps.

### Building from source (optional)

To rebuild the compiler yourself, PXX is seeded from Free Pascal (FPC) once, then
self-hosts:

```sh
make bootstrap      # FPC builds pxx, then pxx rebuilds itself to a fixed point
```

This produces `compiler/pascal26`. You only need FPC for this first bootstrap
(`sudo apt install fpc` on Debian/Ubuntu).

## Your first program

`hello.pas`:

```pascal
program hello;
begin
  writeln('Hello, world!');
end.
```

Compile and run:

```sh
$ ./pxx hello.pas hello
ok: hello  [code=31425B  data=104B  bss=4217B  procs=42]
$ ./hello
Hello, world!
```

PXX writes a complete Linux ELF executable directly — no `as`, no `ld`.

## Debugging with gdb

Add `-g` to emit DWARF debug info:

```sh
$ ./pxx -g hello.pas hello
$ gdb ./hello
(gdb) break hello.pas:3
(gdb) run
Breakpoint 1, hello () at hello.pas:3
3         writeln('Hello, world!');
```

Line stepping, breakpoints, backtraces (`bt`), and `print` of locals/globals all
work — on x86-64, i386, aarch64, and arm32.

## Cross-compiling

Pass `--target=` to build for another CPU:

```sh
./pxx --target=aarch64 hello.pas hello.a64
./pxx --target=i386    hello.pas hello.i386
./pxx --target=arm32   hello.pas hello.arm
```

Run cross binaries under QEMU user-mode (see the repo's `tools/run_target.sh`).

## Next

- [Language reference](./language/)
- [Standard library](./library/)
