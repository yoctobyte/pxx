---
title: Getting started with C
order: 22
---

# Getting started with C

The same `pxx` compiler that builds Pascal also compiles C. It picks the C
frontend from the `.c` extension; there is no separate tool. Everything on this
page was run with **pin v425** (compiler sha256 `426b2fbf3f08…`) on
2026-09-25, from the root of a checkout set up as in [Install](../install/index.md).

## Hello, world

`hello.c`:

```c
#include <stdio.h>

int main(void)
{
    printf("Hello, world!\n");
    return 0;
}
```

```sh
$ ./pxx hello.c hello
ok: hello  [code=61924B  data=12928B  bss=72488B  procs=915  codeseg=65248B]
$ ./hello
Hello, world!
```

As with Pascal, the figures on the `ok:` line vary between builds; the line to
check is `ok:` and the file name.

## What you get: a static binary

`hello` is 78 KB and has no dynamic loader and no C library dependency:

```sh
$ readelf -d hello
There is no dynamic section in this file.
```

`<stdio.h>` did not come from your system. PXX ships its own C runtime,
`lib/crtl`: its own headers and its own implementation, compiled into your
program alongside your code, with anything unused removed. That is the
default, and it is why the binary runs on any x86-64 Linux machine as it is.

## What the built-in C runtime covers

The built-in runtime implements `stdio.h`, `stdlib.h`, `string.h`, `math.h`,
`ctype.h`, `time.h`, `signal.h`, `setjmp.h`, `unistd.h`, `fcntl.h`,
`locale.h`, `assert.h`, the socket headers, part of `wchar.h` and `wctype.h`,
and a subset of `pthread.h`. A program using only these stays static.

Threads are part of it: a `pthread_create` program builds with
`--threadsafe` and is still static. Without that flag the compiler refuses and
tells you to add it.

```sh
./pxx --threadsafe threads.c threads
```

Full details, and the gaps, are on the [C frontend](../targets/c-frontend.md)
page.

## Using the host's C library instead

`--system-libs` makes the standard headers bind to your system's shared
libraries instead of the built-in runtime:

| Command | What the binary depends on |
| --- | --- |
| `./pxx prog.c prog` (the default) | nothing: static |
| `./pxx --system-libs=m prog.c prog` | `libm.so.6` only; everything else built in |
| `./pxx --system-libs prog.c prog` | `libc.so.6` and `libm.so.6` |

With `--system-libs` (all of libc), a program's `printf` output is flushed at
exit. v424 lost it, because the program does not exit through libc; if you are
on v424, call `fflush(stdout)` before `main` returns.

**Other system libraries, such as zlib, SQLite or GTK, link from C.** A
function declared in a system header binds to that header's shared library
when the library on your machine exports it, so `#include <zlib.h>` records
`libz.so.1` and the program runs. v424 recorded only `libc.so.6`, and the
program failed when started with `undefined symbol: zlibVersion`.

You can also avoid the system library altogether:

- Compile the library's **source** into your program, as the programs below do.
  The result is static.
- Import the library from Pascal (`uses sqlite3`) or from
  [Nil Python](../targets/nil-python.md).

The compiler still warns that the header came from `/usr/include`. A GTK
program also needs `--threadsafe`, because GTK's headers include
`<pthread.h>`.

## A project with several files

`pxx` takes one source file per command. A project of several `.c` files is
built in one of two ways.

`greet.h`:

```c
#ifndef GREET_H
#define GREET_H

int add(int a, int b);
void greet(const char *name);

#endif
```

`greet.c`:

```c
#include <stdio.h>
#include "greet.h"

int add(int a, int b)
{
    return a + b;
}

void greet(const char *name)
{
    printf("Hello, %s!\n", name);
}
```

`main.c`:

```c
#include <stdio.h>
#include "greet.h"

int main(void)
{
    greet("pxx");
    printf("6 * 7 = %d\n", add(6 * 6, 6));
    return 0;
}
```

**Separate objects, linked by PXX itself.** Compile each file to an object,
then link the objects. `--link` is PXX's own linker, so no `ld` or `gcc` is
involved:

```sh
./pxx --emit-obj --function-sections greet.c greet.o
./pxx --emit-obj --function-sections main.c main.o
./pxx --link main.o greet.o prog
./prog
```

```text
Hello, pxx!
6 * 7 = 42
```

`--function-sections` matters for size: each object carries its own copy of
the parts of the runtime it uses, and this flag lets the linker drop the
duplicates. Here it gives 113 KB instead of 566 KB. `--link` is x86-64 only
today, and it prints its section statistics on standard error.

**One translation unit.** A file that includes the others builds as a single
program, and the result is smallest (79 KB here):

```c
/* all.c */
#include "main.c"
#include "greet.c"
```

```sh
./pxx all.c prog
```

This is how the large programs below are built. It needs the files not to
define two `static` things with the same name, since they now share one scope.

## Other CPUs

Add `--target=`. This program uses `qsort`, `snprintf` with a `double`,
`sqrt` and `strlen`:

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static int cmp(const void *a, const void *b)
{
    return *(const int *)a - *(const int *)b;
}

int main(void)
{
    int v[] = { 42, 7, 19, 3 };
    char buf[32];

    qsort(v, 4, sizeof v[0], cmp);
    snprintf(buf, sizeof buf, "%.4f", sqrt(2.0));
    printf("%d %d %d %d | %s | %zu | %d-bit\n", v[0], v[1], v[2], v[3], buf,
           strlen(buf), (int)(8 * sizeof(void *)));
    return 0;
}
```

```sh
./pxx --target=aarch64 cross.c cross.a64
tools/run_target.sh aarch64 cross.a64
```

Built with v425 and run under QEMU user mode (wasm32 under wasmtime), each
output matches GCC's build of the same file on x86-64:

| Target | Output |
| --- | --- |
| x86-64 | `3 7 19 42 \| 1.4142 \| 6 \| 64-bit` |
| i386 | `3 7 19 42 \| 1.4142 \| 6 \| 32-bit` |
| aarch64 | `3 7 19 42 \| 1.4142 \| 6 \| 64-bit` |
| arm32 | `3 7 19 42 \| 1.4142 \| 6 \| 32-bit` |
| riscv32 | `3 7 19 42 \| 1.4142 \| 6 \| 32-bit` |
| wasm32 | `3 7 19 42 \| 1.4142 \| 6 \| 32-bit` |

v424 refused any wasm32 C program that includes `math.h`, with
`wasm: var-name pool full`; v425 builds them.

C also runs on the ESP32 chips; see [ESP32](../targets/esp32.md).

## Real programs

Two larger programs show what the C frontend handles. Both are compiled from
their unmodified release sources, and both are in the
[examples showcase](../examples/index.md#real-c-programs) with the exact commands:

- **SQLite 3.46.0**: the whole database engine, built from its single-file
  amalgamation into a static 3.3 MB binary that runs SQL.
- **QuickJS 0.9.0** (quickjs-ng): a JavaScript engine, built in about 11
  seconds into a static 4.9 MB binary whose smoke test matches the expected
  output byte for byte.

Lua, zlib, cJSON and BusyBox are in the same table.

## Next

- [C frontend](../targets/c-frontend.md): the dialect, the preprocessor, and
  known limitations.
- [Known issues in beta 0.1](../reference/known-issues.md)
- [Command-line reference](../reference/cli.md)
