---
title: Known issues in beta 0.1
order: 94
---

# Known issues in beta 0.1

These are the problems we know about in the beta 0.1 compiler, **pin v424**
(commit `0a3a7b5b4`, compiler sha256 `93a336a7ba85…`). Every row was re-run on
v424 on 2026-09-25 before it was listed here; rows that no longer reproduced
were dropped. Pascal and C rows were run on x86-64 Linux, and ESP rows under
Espressif's QEMU on both chips. A row that is fixed in the development tree but
not yet in a pin says so, with a workaround for v424.

Problems that **compile and silently give a wrong answer** come first, because a
refusal at least tells you something is wrong.

## Silently wrong

### C: `sizeof *a` of a two-dimensional array is the size of a pointer

```c
char *table[][4] = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 } };
size_t rows = sizeof table / sizeof *table;   /* 8 here; GCC gives 2 */
```

`sizeof *table` is 8 instead of 32, so the common `sizeof a / sizeof *a`
row count comes out too large and a loop over it runs past the end of the
array. `sizeof table[0]` is correct. This affects every multidimensional array,
global or local, in v424 and in the development tree.
**Workaround:** write `sizeof a[0]` instead of `sizeof *a`.

### C: a typedef of an array of a typedef'd array loses a dimension

```c
typedef float vec4[4];
typedef vec4 mat4[4];
mat4 m = { { 1, 2, 3, 4 }, { 5, 6, 7, 8 }, { 9, 10, 11, 12 }, { 13, 14, 15, 16 } };
```

At file scope `sizeof m` is 16 instead of 64, and every element reads 0. Inside
a function the same initialised declaration is refused with `expected C
expression`. This affects v424 and the development tree.
**Workaround:** declare the variable as `vec4 m[4]`, which gives the right size
and values.

### C: `long double` is 8 bytes

GCC's `long double` is 16 bytes on x86-64; PXX's is 8, the same as `double`. A
single program is consistent with itself, but a struct that contains one has a
different size from GCC's: `struct { char c; long double y; }` is 16 bytes here
and 32 under GCC. That matters as soon as such a struct crosses into
GCC-compiled code or into a file format.

### C: an initialised `__thread` variable reads 0 in other threads

`__thread int tl = 7;` reads 7 in `main` and 0 in a thread started with
`pthread_create`. **Workaround:** assign the value at the start of each thread.

### ESP: bare-metal images do not run on a real chip

Images built with `--esp-profile=bare` fault on the first byte access to a
global or a string, and their UART output is lost. Measured on an ESP32-S3; a
bare ESP32-C3 image has never been run on silicon. They run under Espressif's
QEMU (`qemu-system-xtensa` and `qemu-system-riscv32`), which is what the bare
profile is for. esptool cannot convert a bare ELF either, since it has no
section headers. **Workaround:** on hardware, build the program as an ESP-IDF
component (the default); see [ESP32](../targets/esp32.md).

### ESP: an uncaught exception does not report itself

On a desktop target an unhandled exception prints a message and the program
exits. On the ESP32-C3 the chip reboots and runs the program again, in a loop.
On the ESP32-S3 the program stops after its last output line, with no message.
**Workaround:** catch exceptions at the top level of the program.

### ESP: `Trunc` of an out-of-range float into a 32-bit integer wraps

`Trunc(1e30)` stored in a `LongInt` gives -1. The same value stored in an
`Int64` saturates to 9223372036854775807. Only the 32-bit case is inconsistent;
see [by design](#by-design-math-errors) for why ESP does not stop on a math
error at all.

## Fixed after v424

These are wrong in v424 and fixed in the development tree, so the next pin, v425,
will carry the fixes. Until then, use the workaround.

- **libc `printf` output is lost.** A Pascal program that calls libc's `printf`
  through a `varargs` external prints nothing, because the program does not exit
  through libc and libc never flushes its buffer. **Workaround:** call
  `fflush(nil)` before the program ends.
- **`writeln` of a function result leaks.** `writeln(F(k))` where `F` returns a
  string leaks one string per call: 190 of 200 were never freed in a loop.
  **Workaround:** assign the result to a local first (`s := F(k); writeln(s)`),
  which frees everything.
- **A type named like a compiler-internal record gets the wrong layout.**
  `type TProc = record A: array[0..99] of Int64; end` has `SizeOf` 1344 instead
  of 800, and an enum named `TSymbol` is 104 bytes instead of 4, with no
  diagnostic. Fourteen names do this. **Workaround:** rename the type.
- **An ESP32-S3 bare-metal program that declares a `Double` and uses managed
  strings** fails to build with `j displacement … is outside the encodable
  range`. The ESP32-C3 and the ESP-IDF mode are not affected. **Workaround:**
  keep floats out of the program, or build it as an ESP-IDF component; see
  [ESP32](../targets/esp32.md), "Mode 1: Bare metal". Fixed in `e0db3791c`: the
  program builds and prints its output under `qemu-system-xtensa`.

Each row was re-checked on 2026-09-25 with a development build (compiler sha256
`5a8648a2450a…`, tree `c570417d8`): `printf` prints `42 ok`, the `writeln` loop
leaves 2 strings live instead of 190, and the two types are 800 and 4 bytes.

The `writeln` row is one leak that was measured and fixed. We are not claiming that
PXX has no other leaks of this kind: a wider check of dynamic-array shapes is
still in progress.

## Refused, with a message

These do not compile, or compile with a warning. None of them produces a wrong
answer silently.

- **Pascal `threadvar` on i386** is refused: only x86-64, aarch64 and arm32
  provide per-thread storage.
- **C `__thread` on i386 and riscv32** compiles with a warning that every thread
  shares one copy. Single-threaded programs are unaffected.
- **C `setvbuf` with full or line buffering** returns nonzero: PXX's C streams
  are unbuffered, and the call says so rather than claiming success.
- **`--shared` on aarch64 and arm32** is refused, as shared-library output is
  x86-64 only. On v424 the message reads like an internal error (`no init/fini
  thunk prologue`); the development tree words it plainly, as i386 already did:
  `shared-library output is x86-64 only`.

## By design: math errors

An embedded device should keep running when a sensor produces a value that
causes a math error. A desktop program should stop and say what happened. So
the two behave differently on purpose:

| | Desktop (Linux, all CPUs) | ESP32-S3 and ESP32-C3 |
| --- | --- | --- |
| Pascal and C: integer `div` / `mod` by zero | runtime error 200, the program stops | gives 0, the program continues |
| Pascal and C: float division by zero | Inf or NaN | Inf or NaN |
| Nil Python: `//` and `%` by zero | `ZeroDivisionError`, except in some shapes that stop with runtime error 200 (see the [Nil Python limits](../targets/nil-python.md#known-limits)) | gives 0, the program continues |
| Nil Python: float `/` by zero | `ZeroDivisionError`, as in CPython | Inf |

Each cell was measured on v424. The ESP column was measured under QEMU on both
chips for Pascal and Nil Python, and on the S3 for C. This
is not a bug to be fixed: if you need a zero divisor to stop an ESP program,
test the divisor yourself.

## Nil Python

Nil Python is Python-ish at best. It compiles Python-shaped source ahead of
time and is not CPython: it does not aim for parity, and it is known to have
plenty of issues. Its measured list of limits is kept on the
[Nil Python page](../targets/nil-python.md#known-limits), and the deliberate
differences from CPython are recorded beside it. On ESP, the model is
MicroPython's assumptions about a small device, such as math errors not halting
the program, not MicroPython's API.

## Reporting a problem

Open an issue at <https://github.com/yoctobyte/pxx/issues> with the smallest
source file that shows the problem, the exact command you ran (including any
`--target=`), what you expected and what you got, and the output of
`./pxx --doctor` with the commit of your checkout (`git log -1 --format=%h`).
A program that compiles and gives a wrong answer is the most useful report you
can send.
