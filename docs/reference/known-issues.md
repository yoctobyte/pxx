---
title: Known issues in beta 0.1
order: 94
---

# Known issues in beta 0.1

These are the problems we know about in the beta 0.1 compiler, **pin v425**
(commit `4fbf33f69`, compiler sha256 `426b2fbf3f08…`). The Pascal and C rows
were re-run on v425 on 2026-09-25, on x86-64 Linux, and the ESP rows under
Espressif's QEMU on both chips, except where a row names another compiler. A row that is fixed in the development tree but not yet in a pin says so,
with a workaround for v425.

Problems that **compile and silently give a wrong answer** come first, because a
refusal at least tells you something is wrong.

## Silently wrong

### C: `long double` is 8 bytes

GCC's `long double` is 16 bytes on x86-64; PXX's is 8, the same as `double`. A
single program is consistent with itself, but a struct that contains one has a
different size from GCC's: `struct { char c; long double y; }` is 16 bytes here
and 32 under GCC. That matters as soon as such a struct crosses into
GCC-compiled code or into a file format.

### C: an initialised `__thread` variable reads 0 in other threads

`__thread int tl = 7;` reads 7 in `main` and 0 in a thread started with
`pthread_create`. **Workaround:** assign the value at the start of each thread.

### C: a member access on a comma expression reads the wrong value

`((void) f(), &t[i])->value` reads garbage instead of `t[i].value`, with no
diagnostic. The comma expression itself is right: assigning it to a pointer
first and then reading `p->value` gives the correct value. stb_ds's `shget`
macro has this shape, so `shget` returns garbage while `shgeti` finds the right
index. **Workaround:** assign the comma expression to a pointer variable first,
or use `shgeti` and index the array yourself.

### C: re-locking a recursive `pthread` mutex hangs

A mutex set to `PTHREAD_MUTEX_RECURSIVE` deadlocks the second time the same
thread locks it, although `pthread_mutexattr_settype` returned 0. SQLite built
with `--threadsafe` hangs in `sqlite3_open` because of this. The C runtime in
the development tree fixes it (`3f28aafab`). It is library source, so a
checkout at or after that commit fixes it with the v425 compiler too.
**Workaround with the v425 checkout:** build SQLite with
`-DSQLITE_THREADSAFE=0`, or avoid re-locking a mutex you already hold.

### Pascal: `.Free` on an element indexed by a function call runs the call four times

`a[Pick(i)].Free` calls `Pick` four times, so a `Pick` with side effects runs
them four times, and the object freed can differ from the one tested for
`nil`. The development tree evaluates it once; it is a compiler change, so it
arrives with the next pin. **Workaround with v425:** put the index in a local
first: `k := Pick(i); a[k].Free`.

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
exits. With v425 under ESP-IDF, the ESP32-C3 panics with a register dump and
no message from the program, and the ESP32-S3 stops after its last output line,
with no message. **Workaround:** catch exceptions at the top level of the
program. The development tree fixes the message (`7eeb3d755`), and it is a
compiler change, so it arrives with the next pin: the program then prints
`Unhandled exception: <Class>: <Message>`, as on a desktop, before it stops.
How the program should end after that, stopping or restarting, is still being
decided. A runtime error such as a range-check failure already prints its
message with v425.

The exception row was measured with v425 under Espressif's QEMU on both chips.
The bare-metal row was measured on a physical ESP32-S3 with v424 and has not
been re-run on the board with v425.

## Memory leaks

Before the beta, every leak test in the tree was re-run on the development tree:
164 automated leak checks, and 49 Pascal shapes on seven targets at `-O0` to
`-O3`, covering strings, dynamic arrays, managed records, interfaces, closures,
exceptions, classes, generics and threads. Each check also ran a deliberate leak
to prove it could catch one. Three Pascal leaks in v425 turned up, all in
`Dispose` and `Finalize`. They are fixed in the development tree, and all are
compiler changes, so the fixes arrive with the next pin:

- **`Dispose(p)` did not finalize the thing `p` points at.** When `p` points at
  a record with a string, dynamic-array, interface or `Variant` field, or at a
  string, dynamic array, interface or `Variant` itself, those were not released:
  16 to 160 bytes were lost per `Dispose`, on every target.
  **Workaround with v425:** call `Finalize(p^)` before `Dispose(p)`.
- **`Finalize` of a whole fixed array of managed elements released only the
  first element.** `Finalize(a)` for `a: array[0..3] of string` kept elements 1
  to 3. The same happened through `Dispose` of a pointer to such an array.
  **Workaround with v425:** finalize the elements in a loop.
- **`Dispose(F())` did not finalize the pointee when the pointer came from a
  function call.** **Workaround with v425:** assign the pointer to a
  variable and dispose of that.

Program-level global variables are not finalized when the program exits. This
is a one-time cost at exit, not a leak that grows while the program runs.

On ESP, networking was soaked under Espressif's QEMU with the development-tree
compiler, and none of these runs showed memory or sockets growing:

| what ran | chip | result |
| --- | --- | --- |
| 10,000 HTTP requests with `urequests` (Nil Python) | ESP32-S3 | 64 bytes in total over 10,000 requests |
| 1,000 sessions each of `ntptime`, `umqtt.simple` and `umqtt.robust` (Nil Python) | ESP32-S3 | 0 bytes per session |
| 3,000 MQTT sessions with `umqtt.simple` (Nil Python) | ESP32-C3 | the same socket number every session; heap flat after the first 25 |
| 320 TCP connections over loopback, server and client in Pascal | ESP32-S3 | 0 bytes over 40 passes |

Each run was checked against a deliberate leak, which it caught. The other
ESP soaks drift by about 0.6 bytes per pass, too little for the instrument to
tell apart from noise.

Two limits apply to these measurements:

- **Wi-Fi on a real chip has not been measured.** All of the above ran over
  QEMU's emulated Ethernet.
- **Long network runs on the ESP32-C3 stop under QEMU** after a few hundred to
  a few thousand requests: the program stops making progress, although memory
  and sockets are not exhausted. At the stall, the emulated network card holds
  received frames and has an interrupt pending that is never delivered, so the
  program waits forever for data that has already arrived. This happens below
  the compiled program, in the emulator's network path, and has not been seen
  on the ESP32-S3. It has not been measured on a physical C3.

## Fixed in v425

These were wrong in the previous pin, v424, and are fixed in v425. Each was
re-run on 2026-09-25 with both pins. If you are still on v424, the workaround
is given.

- **libc `printf` output was lost at exit.** A Pascal program that calls libc's
  `printf` through a `varargs` external printed nothing, because libc never
  flushed its buffer. v425 prints `42 ok`. On v424, call `fflush(nil)` before
  the program ends.
- **`writeln` of a function result leaked.** `writeln(F(k))` where `F` returns a
  string leaked one string per call: 190 of 200 were never freed on v424. On
  v424, assign the result to a local first.
- **C `printf` with a `double` printed wrong values on riscv32** once the call
  had more arguments than fit in registers. This was in the C runtime, so any
  checkout after `64483b8e4` has the fix; v425 prints `1.5 2.5 3.5 4.5` as GCC
  does.
- **A wasm32 C program that includes `math.h` was refused** with
  `wasm: var-name pool full`. v425 builds it and it runs under wasmtime.
- **A type named like a compiler-internal record got the wrong layout.**
  `type TProc = record A: array[0..99] of Int64; end` had `SizeOf` 1344 instead
  of 800 on v424, and an enum named `TSymbol` 104 bytes instead of 4. v425
  gives 800 and 4. On v424, rename the type.
- **An ESP32-S3 bare-metal program that declares a `Double` and uses managed
  strings** failed to build on v424 with `j displacement … is outside the
  encodable range`. v425 builds it, and it prints its output under
  `qemu-system-xtensa`.
- **C `sizeof` of a multidimensional array, a typedef of array typedefs, and
  `sizeof (t)->key`.** On v424, `sizeof *table` for `char *table[][4]` was 8
  instead of 32, a `typedef vec4 mat4[4]` was 16 bytes instead of 64, and
  `sizeof (t)->key` was refused. v425 prints `32 3 64 8 16` for a probe of all
  three, the same as GCC.

## Refused, with a message

These do not compile, or compile with a warning. None of them produces a wrong
answer silently.

- **Pascal `threadvar` on i386** is refused: only x86-64, aarch64 and arm32
  provide per-thread storage.
- **C `__thread` on i386 and riscv32** compiles with a warning that every thread
  shares one copy. Single-threaded programs are unaffected.
- **C `setvbuf` with full or line buffering** returns nonzero: PXX's C streams
  are unbuffered, and the call says so rather than claiming success.
- **`--shared` on aarch64 and arm32** is refused with
  `shared-library output is x86-64 only`, as on i386.
- **C compound literals of an array type** are refused:
  `(vec4){1, 2, 3, 4}` with `typedef float vec4[4]`, `(float[4][4]){...}`, and
  `(mat4){...}` for a typedef of array typedefs. Each gives a parse error such
  as `expected C expression`. cglm's `GLM_MAT4_IDENTITY` has this shape.
  **Workaround:** declare a named array and initialise it.

## By design: `Trunc` of an out-of-range float into a 32-bit integer

`Trunc(1e30)` stored in an `Int64` saturates to 9223372036854775807. Stored in
a `LongInt` it gives -1, the low 32 bits of that saturated value. This is the
same on every target, desktop and ESP (measured with v425). A float that does
not fit the integer type it is truncated into has no meaningful integer value;
test the range first if the input can be that large.

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

Each cell was measured on v425. The desktop column was run on x86-64, i386,
aarch64, arm32 and riscv32 Linux (Nil Python has no hosted riscv32). The ESP
column was measured under Espressif's QEMU on both chips, for Pascal, C and
Nil Python. This is not a bug to be fixed: if you need a zero divisor to stop an ESP program,
test the divisor yourself.

## Nil Python

Nil Python is Python-ish at best. It compiles Python-shaped source ahead of
time and is not CPython: it does not aim for parity, and it is known to have
plenty of issues. Its measured list of limits is kept on the
[Nil Python page](../targets/nil-python.md#known-limits), and the deliberate
differences from CPython are recorded beside it. On ESP, the model is
MicroPython's assumptions about a small device, such as math errors not halting
the program, not MicroPython's API.

Two leaks in v425 are fixed in the development tree, and both are compiler
changes, so they arrive with the next pin:

- When a `for` loop's target variable already held an object before the loop
  started, rebinding it on each iteration did not release the old value, so one
  object was kept per iteration. `for t in ts: t.join()` after an earlier
  `t = Thread(...)` is the case that was measured. Fixed by `5f77c0522`.
  **Workaround with v425:** give the loop variable a fresh name.
- A `lambda` passed straight as an argument, as in
  `sorted(xs, key=lambda v: -v)` or `obj.set(lambda x: x + 1)`, kept its closure
  alive after the call: one object per call. Fixed by `0b6fffa0c`.
  **Workaround with v425:** bind the lambda to a name first
  (`k = lambda v: -v`, then `sorted(xs, key=k)`). A lambda bound to a name was
  always released.

## Reporting a problem

Open an issue at <https://github.com/yoctobyte/pxx/issues> with the smallest
source file that shows the problem, the exact command you ran (including any
`--target=`), what you expected and what you got, and the output of
`./pxx --doctor` with the commit of your checkout (`git log -1 --format=%h`).
A program that compiles and gives a wrong answer is the most useful report you
can send.
