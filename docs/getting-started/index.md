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

If that build instead says `unit source not found`, the compiler is looking in
the wrong place rather than the program being wrong. Run `pxx --where`: it
prints every root it resolves and marks the missing ones, and it needs no source
file. See [checking an install](../install/#checking-an-install-and-fixing-unit-source-not-found).

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

## Other frontends

The same compiler also accepts `.c` and `.npy` source directly — the frontend
is chosen by extension, no separate tool:

```sh
./pxx hello.c hello_c
./pxx hello.npy hello_npy   # or hello.py — same frontend, either extension
```

See [C Frontend](../targets/c-frontend.md) and [Nil Python](../targets/nil-python.md).

## What you just built: a binary that needs nothing

`hello` above is not linked against libc. It is a static ELF whose only runtime
dependency is the Linux kernel:

```sh
$ ldd hello
	not a dynamic executable
```

That is the default, for every frontend — not a `--static` flag you remember to
pass. PXX ships its own runtime, so a Pascal, C, or Nil Python program compiles
to something you can copy to another machine of the same architecture and run.

## Importing across languages

Frontends share one backend, one symbol table, and one import resolver, so an
import does not care which language the thing it finds was written in. There is
no wrapper to generate, no FFI block to hand-write, no IDL.

The clearest case is a Python file reaching a C library through the header your
distribution already installed:

```python
import sqlite3
print(sqlite3_libversion_number())
```

```sh
$ ./pxx ver.npy ver && ./ver
3045001
```

`import sqlite3` found `sqlite3.h`, read the real declarations out of it, and
linked `libsqlite3.so.0` — the version printed is whatever the host has. Nothing
was written by hand to make that call reachable.

The same resolver is why `uses gtk3_c;` in Pascal reads a plain C header, and
why `import re` in Nil Python lands on a genuine Pascal unit
(`lib/rtl/re.pas`). See [Cross languages](../targets/cross-languages.md) for the
whole model, including the parts that do not work yet.

### Two ways to get a library, and what each costs

Importing a system library is the one thing that gives up the property above —
`ver` needs `libsqlite3.so.0` at runtime, so it is a normal dynamic binary. That
is a deliberate trade, not a limitation, and you can decline it: point the
compiler at the library's **source** and it compiles that in instead.

```sh
./pxx -Ilib/crtl/include -Ilib/crtl/src -Ipath/to/sqlite prog.c prog
```

with the C side pulling the implementation in directly:

```c
#include "sqlite3.c"
```

Now SQLite is *part of* your binary, dead-code-eliminated with everything else,
and `ldd` again reports no dynamic dependencies. Both routes are exercised by
the same gate: `make test-sqlite-parity` builds one program against the system
`libsqlite3.so.0` and another over the self-compiled amalgamation, runs the
identical workload through both, and requires their output to match byte for
byte.

So the two headline properties are not in tension. Zero-dependency static output
is the default; reaching into the system's shared libraries is available when
you want it, and costs exactly the dependency you asked for.

## Next

- [Language](../language/)
- [Standard library](../library/)
- [Examples](../examples/)
- [Targets](../targets/)
