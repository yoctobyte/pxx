---
title: Getting started
order: 10
---

# Getting started

## Build the compiler

PXX is seeded from Free Pascal (FPC) once, then self-hosts. From a clone:

```sh
make bootstrap      # FPC builds pxx, then pxx rebuilds itself to a fixed point
```

This produces `compiler/pascal26`, the self-hosted compiler. (You only need FPC
installed for this first bootstrap; `sudo apt install fpc` on Debian/Ubuntu.)

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
$ ./compiler/pascal26 hello.pas hello
ok: hello  [code=31425B  data=104B  bss=4217B  procs=42]
$ ./hello
Hello, world!
```

PXX writes a complete Linux ELF executable directly — no `as`, no `ld`.

## Debugging with gdb

Add `-g` to emit DWARF debug info:

```sh
$ ./compiler/pascal26 -g hello.pas hello
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
./compiler/pascal26 --target=aarch64 hello.pas hello.a64
./compiler/pascal26 --target=i386    hello.pas hello.i386
./compiler/pascal26 --target=arm32   hello.pas hello.arm
```

Run cross binaries under QEMU user-mode (see the repo's `tools/run_target.sh`).

## Next

- [Language reference](./language/)
- [Standard library](./library/)
