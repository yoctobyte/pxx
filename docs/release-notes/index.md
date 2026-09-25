---
title: Beta 0.1 release notes (draft)
order: 95
---

# Beta 0.1 release notes — draft

> **Draft. No release has been cut.** Where beta 0.1 will be published, what it
> will be tagged, and whether it ships as source, as binaries or both are not
> decided yet, so nothing below assumes any of them. Until a release exists,
> the way to get PXX is a clone of the repository; see [Install](../install/).

Everything on this page was measured on an x86-64 Linux host against **pin
v424**: commit `0a3a7b5b4`, compiler binary sha256 `93a336a7ba85…`, on
2026-09-25. This is the compiler that `./pxx` runs in a checkout of that commit.
Where a figure was measured with a different compiler, it says which. If you
are reading this against a later pin, the figures describe v424, not yours.

The one exception is [Fixed since v424](#fixed-since-v424): those fixes are in
the development tree and were measured there, and the next pin, v425, will be
the first to carry them.

## What PXX is

A self-hosting compiler for the Pascal dialect of Free Pascal, written from
scratch. It has its own runtime library, its own ELF writer and its own linker,
so it produces finished executables with no `as`, `ld` or libc involved. It
compiles itself to a byte-identical binary. The same backend also compiles C
and Nil Python (a Python-shaped language), and it targets several CPUs and the
ESP32 family.

By default a compiled program is a static ELF whose only runtime dependency is
the Linux kernel. That holds for every frontend.

## What works

The [examples showcase](../examples/index.md) is the best answer: every entry on it was
compiled and run with pin v423, and all its example programs were rebuilt
with v424, where the batch programs printed identical output. It shows the
output or a screenshot of each. The highlights:

- **Pascal:** terminal and GTK applications, an IDE written in PXX, a chess
  engine, a parallel `for` loop, and the compiler itself, which PXX builds to a
  byte-identical copy.
- **C:** real code compiled unmodified and checked against GCC's build of the
  same sources: SQLite 3.46.0, Lua 5.4.7, zlib 1.3.1, cJSON 1.7.18, BusyBox,
  and the QuickJS 0.9.0 JavaScript engine. See
  [Getting started with C](../getting-started/c.md).
- **ESP32:** Pascal, C and Nil Python programs on the ESP32-S3 and ESP32-C3,
  with units for GPIO, UART, ADC, PWM, I2C, stored settings and timers, and a
  walk of the examples on a physical ESP32-S3 board. See [ESP32](#esp32) below.
- **Nil Python:** a program shown beside CPython with the frame rate of each,
  and a Nil Python program driving GPIO and a timer on the ESP32-S3 board.
- [A minimal bootable Linux system](../examples/minimal-linux-system.md) whose
  shell and compiler were built by PXX.

## Languages

| Language | State |
| --- | --- |
| **Pascal** | Solid. FPC's `objfpc` and Delphi modes: classes, interfaces, generics, managed strings, dynamic arrays, exceptions, threads. The target is correct Pascal compiled correctly; we do not reproduce FPC behaviour for its own sake. See [FPC compatibility](../language/fpc-compatibility.md). |
| **C** | Solid. A C99-class dialect with common GNU extensions and PXX's own C runtime (`lib/crtl`). The corpus above compiles and its output matches GCC's; zlib needs one struct tag added when built as a single file, as the showcase explains. See [C frontend](../targets/c-frontend.md). |
| **Nil Python** | Python-ish, and known to have plenty of issues. It compiles Python-shaped source ahead of time to a static binary; it is not CPython and does not run CPython's standard library. Imports resolve to PXX's own implementations first, and several of those cover only part of the Python module they are named after. See [Nil Python](../targets/nil-python.md). |
| **BASIC** | A small real frontend with its own dialect. |
| **Rust, Zig** | Experimental proofs of concept. Do not build on them. |
| Ada, Fortran, Algol, Erlang, LOLCODE, Whitespace | Skeleton probes, one test each. Listed by `pxx --version`; not a support claim. |

[Other frontends](../targets/other-frontends.md) explains the last three rows.

## Targets

The same one-line program, `writeln(6*7)` or its equivalent in each language,
compiled by pin v424 and run: natively on x86-64, under QEMU user mode for the
other Linux targets (`tools/run_target.sh`), and under wasmtime for wasm32.

| | x86-64 | i386 | aarch64 | arm32 | riscv32 | wasm32 |
| --- | --- | --- | --- | --- | --- | --- |
| Pascal | 42 | 42 | 42 | 42 | 42 | 42 |
| C | 42 | 42 | 42 | 42 | 42 | 42 |
| Nil Python | 42 | 42 | 42 | 42 | refuses | 42 |
| Rust | 42 | 42 | 42 | 42 | 42 | refuses |
| Zig | 42 | 42 | 42 | 42 | 42 | refuses |

A **refusal** is a compile-time error that names the reason, for example
*"a heap arena needs mmap"* for Nil Python on riscv32. It is not a crash.

- x86-64 is the host and the most heavily tested target.
- wasm32 is the least tested: its suites are run by hand, not continuously.
- ESP32 (xtensa and riscv32) is covered in the next section. See
  [Cross-compilation](../targets/cross-compilation.md) for the flags.

## ESP32

PXX builds ESP-IDF and bare-metal images for esp32s3 (xtensa) and esp32c3
(riscv32), from Pascal, C and Nil Python. Bare-metal images are for QEMU only:
on a real ESP32-S3 they fault on the first byte access, so use the ESP-IDF
profile on hardware.

- **C conformance:** 219 pass, 0 fail, 1 skip out of the 220 single-program
  tests of c-testsuite, compiled for esp32s3 and run under Espressif's QEMU
  (`tools/run_c_conformance_esp.sh --chip esp32s3`). The skip is `00187.c`,
  which needs a writable file system the test image does not mount. This was
  measured with a development compiler (binary sha256 `9bcd11d46816`, tree
  `e1648bcb4`) that predates v423, not with v424 itself.
- **Examples:** 15 programs in `examples/esp32/` run under QEMU with pin v423
  and are listed in the [showcase](../examples/#esp32).
- **On a board:** the ESP lane ran all 15 ESP32-S3 examples on one physical
  ESP32-S3 board (ESP-IDF v6.0.1), built with the v424 compiler, and all 15
  passed. That includes the GPIO-edge and ADC programs, which QEMU cannot
  exercise, and two Nil Python programs. The ESP32-C3 has been run only under
  QEMU, and the ESP32-S2 has only been built.
- **Peripheral units:** GPIO with edge events (`espgpio`, `interrupts`), UART
  (`espuart`), continuous ADC (`espadc`), PWM (`esppwm`), I2C (`espi2c`), stored
  settings (`espnvs`), timers (`esptimer`) and heap figures (`espsys`), each
  usable from Pascal and from Nil Python. Their interfaces, examples and limits
  are in [ESP32 peripherals](../library/esp.md). `espuart` is newer than v424's
  commit; it is library source, so the v424 compiler builds it from a checkout
  that has it. **Reading and writing a real I2C device has not been tested
  yet**; the board checks covered the bus without a device.
- **Memory over time:** the ESP lane ran the examples in a loop on the S3
  board. With pin v424, `print` of a number leaked memory on every pass
  (44 bytes per pass in `nilpy-s3`, 220 in `nilpy-hw-s3`, 264 in
  `gpio-edge-s3`), and on xtensa every comparison of a function's string
  result leaked too. Both are [fixed since v424](#fixed-since-v424). With a
  development compiler that has the fixes (sha256 `29956ba5beff…`, tree
  `9c14efd7b`), those three examples lose 0 bytes per pass. The Nil Python
  monitor example, `monitor-s3`, ran 193 reports over a 3.5-minute soak with
  free heap flat, with that compiler and with v424. The timer, PWM, I2C and
  UART units lose 0 bytes over 300 open/use/close cycles each. With v424,
  `adc-s3` in a loop loses about 17.5 KB per pass, because an `adc.read()`
  whose result is thrown away is never freed. Assigning the result or looping
  over it avoids that, and it is
  [fixed since v424](#fixed-since-v424).

ESP is not a Unix: FreeRTOS provides tasks, not processes. Calls with POSIX
shapes that have no meaning there return an explicit "unsupported" error rather
than a plausible wrong answer. To start, follow
[Getting started on the ESP32](../getting-started/esp32.md): installing
ESP-IDF, then a first Pascal, C and Nil Python program.

## Fixed since v424

These fixes are in the development tree, not in v424; pin v425 will carry
them. Unless a row says otherwise, each was checked on 2026-09-25 by running
the same program with v424 and with a development build (compiler sha256
`5a8648a2450a…`, tree `c570417d8`).

| Fix | Commit | What changes |
| --- | --- | --- |
| `print` / `writeln` of a function result leaks | `e7a07c9cd` | Writing a string that a function returned no longer leaks it, on every backend. `writeln(F(k))` 200 times: 190 strings live on v424, 2 now. For Nil Python every `print` of a number, float or container leaked one string; on the ESP32-S3 that was 44 bytes per run. |
| xtensa: comparing a function's string result leaks | `3671e2940` | `if F(4) <> 'soak'` leaked the result on every evaluation, on xtensa only. Measured by its author: 0 bytes per iteration on the ESP32-S3 board afterwards. |
| libc `printf` output lost at exit | `dde6816ce`, `93a03391c` | A program that imports from libc now flushes libc's buffers at exit. v424 printed nothing; the development build prints `42 ok`. The follow-up keeps programs that only reach libc weakly, such as threaded ones, static. |
| A type named like a compiler-internal record gets the wrong layout | `74ebf5593` | `type TProc = record A: array[0..99] of Int64; end` is 800 bytes, as in FPC (v424: 1344). An enum named `TSymbol` is 4 bytes (v424: 104). A class named `TProc` no longer crashes in `Free` (measured by its author). |
| `SizeOf` of a class type gave the instance size | `2b06006e1` | `SizeOf(TFoo)` for a class type is now the reference width, the same as `SizeOf` of a variable of that type and as FPC: 8 on x86-64 (v424: 32 for a class with three `Int64` fields), 4 on i386 and arm32. On v424, `Move(f, g, SizeOf(TFoo))` between two class references copied past the variable. Checked with development build `fa329b3bc6aa…`. |
| riscv32 could not export a routine to C | `73ed7a4e4` | `exports f` for a `cdecl` routine now works on riscv32, so a C program in an ESP32-C3 build can link and call it. xtensa still refuses, and the message says why. Measured by its author. |
| `--shared` off x86-64 reads like an internal error | `45bbfb187` | On aarch64 and arm32, `--shared` now says `shared-library output is x86-64 only`, as i386 did. v424 said `internal: no init/fini thunk prologue`. |
| A `var` argument of the wrong width through an overloaded routine | `6ff482413` | The refusal now names the parameter and both widths, where v424 said only `no overload of M matches these arguments`. Measured by its author. |
| C `struct tm` lacks `tm_gmtoff` and `tm_zone` | `f82b42a21` | The C runtime's `struct tm` has both fields and honours `TZ=":zone"`. This is runtime-library source, so v424 picks it up from a checkout at or after the commit; it is what lets QuickJS build. |
| tcc does not compile | `3c1952549`, `8d32d8c8a` | PXX compiles the Tiny C Compiler again, and that tcc compiles C and itself byte-identical to a GCC-built tcc (measured with compiler `5852ed1d21c6…`, tree `ed6297d5b`). The first commit is in the C runtime, so with v424 and a current checkout the build gets further, but it still stops at an `#include` inside a function call's arguments in `tccpp.c`. `tcc -run` does not work: it needs glibc's `libc.so.6` at run time. |
| C `sizeof` of a dereferenced array, a typedef of array typedefs, `sizeof (t)->key` | `7b781ce15` | `sizeof *table` for `char *table[][4]` is 32, not 8, so `sizeof a / sizeof *a` counts rows correctly. `typedef vec4 mat4[4]` is 64 bytes and can be initialised as a local, and `sizeof (t)->key` parses. A probe of all three prints the same as gcc (`32 3 64 8 16`), where v424 refuses it. tiny-regex-c's own `test1`, which counts its test table this way, crashed on v424 and now passes 76 of 76, with output identical to gcc's; its `test2` and `test_compile` match gcc too. Measured with compiler `9be250c24665…`, tree `7b781ce15`. |
| A discarded class result from a dotted call leaks (`adc.read()`) | `c4eb85dc39` | In Nil Python, a call such as `adc.read()` or `h.make()` used as a bare statement now releases the object it returns, as the assigned form always did. The fix's own test leaves 1,002 objects live on v424 and 6 with the fix (compiler `790bc11fb9c2…`, tree `f35e6ff62`). On the ESP32-S3 board, `adc-s3` looped 60 times keeps its free heap at 271,232 bytes from the first pass to the last, where a compiler without the fix fell from 253,688 to 78,252 bytes by pass 10 (board run by the ESP lane, compiler `790bc11fb9c2…`, ESP-IDF v6.0.1). |

## Known issues

The full list, each row re-run on v424, is on its own page:
[Known issues in beta 0.1](../reference/known-issues.md). In short:

- A few programs compile and silently give a wrong answer. Examples: C
  `long double` is 8 bytes, not GCC's 16; an initialised C `__thread` variable
  reads 0 outside the main thread; on ESP, an uncaught exception reboots or
  stops the chip without a message.
- Several problems in v424 are fixed in the development tree, listed in
  [Fixed since v424](#fixed-since-v424). The known-issues page gives a
  workaround for each until v425.
- Integer division by zero gives 0 on ESP and stops the program on desktop.
  That is by design: an embedded device keeps running.
- Nil Python is Python-ish at best and known to have plenty of issues; its
  measured limits are on the
  [Nil Python page](../targets/nil-python.md#known-limits).

## Reporting bugs

Open an issue at <https://github.com/yoctobyte/pxx/issues>. The most useful
report contains:

1. the smallest source file that shows the problem;
2. the exact command you ran, including `--target=` if any;
3. what you expected and what you got (for C, GCC's output is a good
   "expected"; for Pascal, FPC's; for Nil Python, CPython's);
4. the output of `./pxx --doctor`, and the commit of your checkout
   (`git log -1 --format=%h`).

**Programs that compile and quietly give a wrong answer are the most valuable
reports.** A refusal with a clear message is usually already known; a wrong
answer usually is not.

Contributions are welcome under the terms in `CONTRIBUTING.md` in the
repository.
