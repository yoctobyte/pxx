---
title: Getting started
order: 20
---

# Getting started

Start here after [installing PXX](../install/). This section walks through the
smallest useful program, then points to language, library, and target docs.

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

See [First program](./first-program.md) for the same example with a short
explanation of the source layout and compiler arguments.

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

- [Language](../language/)
- [Standard library](../library/)
- [Targets](../targets/)
