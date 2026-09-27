---
title: Beta 0.1 release notes (draft)
order: 95
---

# Beta 0.1 release notes — draft

> **Draft. The release has not been tagged or published yet.** Beta 0.1
> "Blaise" is pin v441. Where it will be published and whether it ships as
> source, as binaries or both are not decided yet, so nothing below assumes
> either. Until then, the way to get PXX is a clone of the repository; see
> [Install](../install/index.md).

This page describes **pin v441**: commit `5c1696ca79`, compiler binary sha256
`4ebfa2d047a2…`. That is the compiler `./pxx` runs in a checkout of that
commit. Figures were measured with v441 on an x86-64 Linux host on 2026-09-26
and 2026-09-27, unless a figure names another compiler; figures kept from
the draft pin v425 (commit `4fbf33f69`, sha256 `426b2fbf3f08…`) or an
earlier compiler say so. If you are reading this against a later pin, the
figures describe v441, not yours.

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
compiled and run with pin v423, and its example programs were rebuilt with
v424, v425 and v441, where the batch programs printed identical output. It shows the
output or a screenshot of each. The highlights:

- **Pascal:** terminal and GTK applications, an IDE written in PXX, a chess
  engine, a parallel `for` loop, and the compiler itself, which PXX builds to a
  byte-identical copy.
- **C:** real code compiled unmodified and checked against GCC's build of the
  same sources: SQLite 3.46.0, Lua 5.4.7, zlib 1.3.1, cJSON 1.7.18, BusyBox,
  the QuickJS 0.9.0 JavaScript engine, the Tiny C Compiler, tiny-regex-c and
  the ENet networking library. See
  [Getting started with C](../getting-started/c.md).
- **ESP32:** Pascal, C and Nil Python programs on the ESP32-S3 and ESP32-C3,
  with units for GPIO, UART, ADC, PWM, I2C, stored settings and timers, and a
  walk of the examples on a physical ESP32-S3 board. See [ESP32](#esp32) below.
- **Nil Python:** lekkerzeilen, a 3D sailing simulator written in ordinary
  Python, compiled into one native binary and shown beside CPython (still much
  slower; the showcase gives its one measured scene), and a Nil Python program driving GPIO and a timer on the ESP32-S3 board.
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
compiled by pin v441 and run: natively on x86-64, under QEMU user mode for the
other Linux targets (`tools/run_target.sh`), and under wasmtime for wasm32.

| | x86-64 | i386 | aarch64 | arm32 | riscv32 | wasm32 |
| --- | --- | --- | --- | --- | --- | --- |
| Pascal | 42 | 42 | 42 | 42 | 42 | 42 |
| C | 42 | 42 | 42 | 42 | 42 | 42 |
| Nil Python | 42 | 42 | 42 | 42 | refuses | 42 |
| Rust | 42 | 42 | 42 | 42 | 42 | refuses |
| Zig | 42 | 42 | 42 | 42 | 42 | refuses |

A **refusal** is a compile-time error that names the reason, for example
*"Nil Python is not supported on hosted riscv32 Linux yet; build it for the
ESP32 instead"*. It is not a crash. The table is the same as with the draft
pin v425.

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
  which needs a writable file system the test image does not mount. Measured
  with v441 on 2026-09-27; the draft pin v425 gave the same result on
  2026-09-25. The same 220 compiled for esp32c3 (`--chip esp32c3`) give the
  same result with v441: 219 pass, 0 fail, the same skip.
- **Examples under QEMU:** with v441, all 13 QEMU runs in the
  [showcase](../examples/index.md#esp32) pass, each judged by its expected
  output or its own verdict line: `hello` on both chips and eleven example
  projects on the S3 and the C3.
- **On a board:** with v441, on one physical ESP32-S3 (rev v0.2, MAC
  `50:78:7d:14:23:10`, ESP-IDF v6.0.1), all of the following passed:
  - the 12 `-s3` examples of the v425 walk: `nilpy-s3`, `nilpy-hw-s3`,
    `gpio-edge-s3` and `adc-s3` match their expected output; `hello-s3`,
    `timer-s3`, `rgb-s3`, `i2c-s3`, `pwm-s3`, `uart-s3`, `nvs-s3` and
    `wifi-ap-s3` print their own pass lines;
  - the two short forms (a Pascal program and a C program), which match the
    PC;
  - `spi-s3`, `monitor-s3` and the Wi-Fi station page `nilpy-station-s3`;
  - the Nil Python socket-error test.

  The v425 walk named 14 of these and reported them as 15. That list includes
  the GPIO-edge and ADC programs, which QEMU cannot exercise. After the
  release, on 2026-09-27, the ESP32-C3 examples were run on a physical C3
  board with the same v441 compiler, and all passed (see the
  [showcase](../examples/index.md#on-a-real-esp32-c3)). The ESP32-S2 has only
  been built.
- **Peripheral units:** GPIO with edge events (`espgpio`, `interrupts`), UART
  (`espuart`), continuous ADC (`espadc`), PWM (`esppwm`), I2C (`espi2c`), SPI (`espspi`), stored
  settings (`espnvs`), timers (`esptimer`) and heap figures (`espsys`), each
  usable from Pascal and from Nil Python. Their interfaces, examples and limits
  are in [ESP32 peripherals](../library/esp.md). **Talking to a real I2C or SPI device has not
  been tested yet**; the board checks covered each bus without a device.
- **Memory over time:** the ESP lane ran the examples in a loop on the S3
  board. With v424, `print` of a number leaked memory on every pass (44 bytes
  per pass in `nilpy-s3`, 220 in `nilpy-hw-s3`, 264 in `gpio-edge-s3`), on
  xtensa every comparison of a function's string result leaked too, and
  `adc-s3` lost about 17.5 KB per pass because a discarded `adc.read()` was
  never freed. All three are [fixed in v425](#fixed-in-v425). With a compiler
  that has the first two fixes (sha256 `29956ba5beff…`, tree `9c14efd7b`),
  those three examples lose 0 bytes per pass, and the Nil Python monitor
  example, `monitor-s3`, ran 193 reports over a 3.5-minute soak with free heap
  flat. With v425 itself, `adc-s3` looped 60 times keeps its free heap at
  271,232 bytes from the first pass to the last. With development compilers
  before v425, the timer, PWM, I2C and UART units lost 0 bytes over 300
  open/use/close cycles each. These loops were not repeated with v441. The
  leak sweep for this release covered ESP networking under QEMU; see
  [Known issues](../reference/known-issues.md#esp-networking).

ESP is not a Unix: FreeRTOS provides tasks, not processes. Calls with POSIX
shapes that have no meaning there return an explicit "unsupported" error rather
than a plausible wrong answer. To start, follow
[Getting started on the ESP32](../getting-started/esp32.md): installing
ESP-IDF, then a first Pascal, C and Nil Python program.

## Fixed in v425

These were wrong in pin v424 and are fixed in the draft pin v425, and so in
v441, which descends from it. Unless a row says otherwise, each was checked on
2026-09-25 by running the same program with v424 and with v425; the numbers
below are from those two compilers. What was fixed between v425 and v441 is
listed under
[Fixed in this release](../reference/known-issues.md#fixed-in-this-release).

| Fix | Commit | What changes |
| --- | --- | --- |
| `print` / `writeln` of a function result leaks | `e7a07c9cd` | Writing a string that a function returned no longer leaks it, on every backend. `writeln(F(k))` 200 times: 190 strings live on v424, 2 on v425. For Nil Python every `print` of a number, float or container leaked one string; on the ESP32-S3 that was 44 bytes per run. |
| xtensa: comparing a function's string result leaks | `3671e2940` | `if F(4) <> 'soak'` leaked the result on every evaluation, on xtensa only. Measured by its author: 0 bytes per iteration on the ESP32-S3 board afterwards. |
| libc `printf` output lost at exit | `dde6816ce`, `93a03391c` | A program that imports from libc now flushes libc's buffers at exit. v424 printed nothing; v425 prints `42 ok`. The follow-up keeps programs that only reach libc weakly, such as threaded ones, static. |
| A type named like a compiler-internal record gets the wrong layout | `74ebf5593` | `type TProc = record A: array[0..99] of Int64; end` is 800 bytes, as in FPC (v424: 1344). An enum named `TSymbol` is 4 bytes (v424: 104). A class named `TProc` no longer crashes in `Free` (measured by its author). |
| `SizeOf` of a class type gave the instance size | `2b06006e1` | `SizeOf(TFoo)` for a class type is now the reference width, the same as `SizeOf` of a variable of that type and as FPC: 8 on x86-64 (v424: 32 for a class with three `Int64` fields), 4 on i386 and arm32. On v424, `Move(f, g, SizeOf(TFoo))` between two class references copied past the variable. |
| riscv32 could not export a routine to C | `73ed7a4e4` | `exports f` for a `cdecl` routine now works on riscv32, so a C program in an ESP32-C3 build can link and call it. xtensa still refuses, and the message says why. v425 builds the object; linking and running it was measured by the fix's author. |
| `--shared` off x86-64 reads like an internal error | `45bbfb187` | On aarch64 and arm32, `--shared` now says `shared-library output is x86-64 only`, as i386 did. v424 said `internal: no init/fini thunk prologue`. |
| A `var` argument of the wrong width through an overloaded routine | `6ff482413` | The refusal now names the parameter and both widths, where v424 said only `no overload of M matches these arguments`. Measured by its author. |
| C `struct tm` lacks `tm_gmtoff` and `tm_zone` | `f82b42a21` | The C runtime's `struct tm` has both fields and honours `TZ=":zone"`. This is runtime-library source, so any checkout at or after the commit has it; it is what lets QuickJS build. |
| tcc does not compile | `3c1952549`, `8d32d8c8a` | v424 stopped in `tccpp.c`. v425 compiles the Tiny C Compiler, and that tcc compiles a program to the same executable as a GCC-built tcc, and compiles itself to the same binary as a GCC-built tcc does, which in turn reproduces itself. That tcc cannot use `-run`; a separate build can, see [Status](../reference/status.md). |
| C `sizeof` of a dereferenced array, a typedef of array typedefs, `sizeof (t)->key` | `7b781ce15` | `sizeof *table` for `char *table[][4]` is 32, not 8, so `sizeof a / sizeof *a` counts rows correctly. `typedef vec4 mat4[4]` is 64 bytes and can be initialised as a local, and `sizeof (t)->key` parses. A probe of all three prints the same as gcc (`32 3 64 8 16`), where v424 refuses it. tiny-regex-c's own `test1`, which counts its test table this way, crashed on v424 and passes 76 of 76 on v425, with output identical to gcc's; its `test2` and `test_compile` match gcc too. |
| A discarded class result from a dotted call leaks (`adc.read()`) | `c4eb85dc39` | In Nil Python, a call such as `adc.read()` or `h.make()` used as a bare statement now releases the object it returns, as the assigned form always did. The fix's own test leaves 1,002 objects live on v424 and 6 with the fix (compiler `790bc11fb9c2…`, tree `f35e6ff62`). On the ESP32-S3 board with v425, `adc-s3` looped 60 times keeps its free heap at 271,232 bytes from the first pass to the last, where a compiler without the fix (sha256 `bb17d23beea5…`) fell from 253,688 to 78,252 bytes by pass 10 (board runs by the ESP lane, ESP-IDF v6.0.1). |
| C `printf` of a `double` on riscv32 | `64483b8e4` | Once a call had more arguments than fit in registers, the extra `double`s printed as a tiny number or garbage. This is in the C runtime; v425 prints `1.5 2.5 3.5 4.5`, as GCC does. |
| wasm32 C with `#include <math.h>` | `c89be3ee6` | v424 refused any such program with `wasm: var-name pool full`. v425 builds it, and it runs under wasmtime. |
| ESP32-S3 bare program with a `Double` and managed strings | `e0db3791c` | v424 failed to build it (`j displacement … is outside the encodable range`). v425 builds it, and it prints its output under `qemu-system-xtensa`. |
| `--list-targets` described wasm32 as having no codegen | `3472ffc42` | v425 lists wasm32 as `via wasmtime`, for Pascal, C and Nil Python. |
| `#include <zlib.h>` did not import zlib | `5eca70e93` | A C program that includes a system library's header now records that library (`libz.so.1` for zlib) and runs. v424 imported every such function from libc, and the program failed at load. |
| A C macro alias of a function-like macro was not rescanned | `473d9aa83` | With `#define F(t) ((t) + 1)`, `#define B F` and `#define A B`, the calls `B(x)` and `A(x)` now expand to `F`'s body as in GCC, at any depth. v424 refused them as calls to an undeclared function. |

## Known issues

The full list, restamped to v441, is on its own page:
[Known issues in beta 0.1](../reference/known-issues.md). In short:

- A few programs compile and silently give a wrong answer. Examples: C
  `long double` is 8 bytes, not GCC's 16; an initialised C `__thread` variable
  reads 0 outside the main thread; a C struct member typed by an array
  typedef of structs (`typedef P PA[2]; struct { PA ps; }`) is too small.
- Three items that were open in the draft pin v425 are fixed in v441: a C
  member access on a comma expression, `(x, p)->field`, read the wrong value;
  C compound literals of an array type were refused; and on ESP an uncaught
  exception stopped the chip without a message.
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
