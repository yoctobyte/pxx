---
title: Beta 0.1 release notes (draft)
order: 95
---

# Beta 0.1 release notes — draft

> **Draft. No release has been cut.** Where beta 0.1 will be published, what it
> will be tagged, and whether it ships as source, as binaries or both are not
> decided yet, so nothing below assumes any of them. Until a release exists,
> the way to get PXX is a clone of the repository; see [Install](../install/).

Everything on this page was measured on **2026-09-24** on an x86-64 Linux host,
against **pin v423**: commit `906239536`, compiler binary sha256
`113a515bbdc9…`. This is the compiler that `./pxx` runs in a checkout of that
commit. If you are reading this against a later pin, the figures describe v423,
not yours.

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

The [examples showcase](../examples/) is the best answer: every entry on it was
compiled and run with this pin, and it shows the output or a screenshot of each.
It covers:

- terminal and GTK applications, an IDE written in PXX, and a chess engine;
- a parallel `for` loop;
- a Nil Python program shown beside CPython, with the frame rate of each;
- ESP32 programs run under QEMU;
- real C code compiled unmodified: SQLite 3.46.0, Lua 5.4.7, zlib 1.3.1,
  cJSON 1.7.18, and BusyBox, checked against GCC's build of the same sources;
- [a minimal bootable Linux system](../examples/minimal-linux-system.md) whose
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
compiled by pin v423 and run: natively on x86-64, under QEMU user mode for the
other Linux targets (`tools/run_target.sh`), and under wasmtime for wasm32.

| | x86-64 | i386 | aarch64 | arm32 | riscv32 | wasm32 |
| --- | --- | --- | --- | --- | --- | --- |
| Pascal | 42 | 42 | 42 | 42 | 42 | **traps** (see known issues) |
| C | 42 | 42 | 42 | 42 | 42 | 42 |
| Nil Python | 42 | 42 | 42 | 42 | refuses | 42 |
| Rust | 42 | 42 | 42 | 42 | 42 | refuses |
| Zig | 42 | 42 | 42 | 42 | 42 | refuses |

A **refusal** is a compile-time error that names the reason, for example
*"a heap arena needs mmap"* for Nil Python on riscv32. It is not a crash.

- x86-64 is the host and the most heavily tested target.
- wasm32 is the least tested: its suites are run by hand, not continuously.
  The C row there was built with the compiler binary directly. Through the
  `./pxx` wrapper, the same C file currently fails with
  `undefined variable (SYS_openat)`, because the wrapper puts the Linux platform
  layer on the search path for every target.
- ESP32 (xtensa and riscv32) is covered in the next section. See
  [Cross-compilation](../targets/cross-compilation.md) for the flags.

## ESP32

PXX builds bare-metal and ESP-IDF images for esp32s3 (xtensa) and esp32c3
(riscv32), from Pascal, C and Nil Python.

- **C conformance:** 219 pass, 0 fail, 1 skip out of the 220 single-program
  tests of c-testsuite, compiled for esp32s3 and run under Espressif's QEMU
  (`tools/run_c_conformance_esp.sh --chip esp32s3`). The skip is `00187.c`,
  which needs a writable file system the test image does not mount. This was
  measured with a development compiler (binary sha256 `9bcd11d46816`, tree
  `e1648bcb4`) that predates v423, not with v423 itself.
- **Examples:** 15 programs in `examples/esp32/` run under QEMU on this pin and
  are listed in the [showcase](../examples/#esp32).
- **On a board:** eight examples, including the GPIO-edge and ADC programs
  that QEMU cannot exercise, ran correctly on a physical ESP32-S3, built with a
  development compiler rather than v423. Looped for minutes, the Nil Python
  examples leak memory on every run. A fix is being landed; until it is in,
  treat Nil Python on ESP as fine for short runs and not yet for long-running
  use. The details are in the [showcase](../examples/#on-a-real-esp32-s3).

ESP is not a Unix: FreeRTOS provides tasks, not processes. Calls with POSIX
shapes that have no meaning there return an explicit "unsupported" error rather
than a plausible wrong answer. A getting-started guide for ESP is being written;
until it lands, see [ESP32](../targets/esp32.md).

## Known issues

These lists are measured, not recalled. The Pascal and C rows were run on this
pin and on the development tree by the Pascal/C lane on 2026-09-24. Rows that
**compile and silently give a wrong answer** come first, because a refusal at
least tells you something is wrong.

### Silently wrong

- **Pascal, every target:** a `var` parameter accepts a narrower variable. For
  example, a `LongInt` passed to `var x: Int64` receives an 8-byte write, which
  overwrites a neighbouring variable. FPC refuses the call. *Workaround:* pass
  a variable of exactly the parameter's type.
- **Pascal, every target:** a record type named like one of fourteen
  compiler-internal records (`TProc` and `TSymbol` among them) silently takes
  the compiler's layout: `SizeOf` is 1344 where it should be 800. *Workaround:*
  rename the type.
- **Pascal, every target except wasm32:** a function that writes into a
  **by-value** string parameter also changes the caller's string. The textbook
  `UpperStr(s: string)` returns the right value and upper-cases the caller's
  variable too. *Fixed after v423*, so it is gone in the next pin. *Workaround
  until then:* copy the parameter into a local first.
- **Pascal, wasm32:** the same by-value problem, which the fix above does not
  reach. In addition, `SetLength` on a by-value dynamic-array parameter has no
  effect. *Workaround:* copy into a local.
- **C, every target:** `long double` is 8 bytes; GCC's is 16. A single program
  is self-consistent, but a struct containing one has a different size from
  GCC's (`struct { char c; long double y; }` is 16 bytes here, 32 under GCC).
  This matters as soon as such a struct crosses into GCC-compiled code or a
  file format.
- **C, threaded targets:** an **initialised** `__thread` variable reads 0 in
  every thread except the main one. *Workaround:* assign the value at the start
  of each thread.
- **ESP (esp32c3, esp32s3):** an uncaught exception does not report itself.
  esp32c3 reboots in a loop; esp32s3 stops with no message. *Workaround:*
  catch exceptions at the top of the program.
- **ESP:** `Trunc` of an out-of-range float wraps when stored into a 32-bit
  integer (`Trunc(1e30)` gives -1) but saturates when stored into an `Int64`.

### Builds "ok" but does not run

- **Pascal on wasm32:** a program that uses `WriteLn` prints `ok:` and exits 0,
  but the module traps as soon as it runs. The compiler does print the reason on
  stderr (`RTL helper PXXWriteDecW not found`), so a wasm32 build that reports
  lowering gaps will not run. C `printf` and Nil Python `print` work on wasm32.

### Refused, with a message that names the problem

- Pascal `threadvar` on i386.
- C `__thread` on i386 and riscv32 compiles with a warning that every thread
  shares one copy. Single-threaded code is unaffected.
- C `setvbuf` with full or line buffering returns nonzero: PXX's C streams are
  unbuffered, and the call says so instead of claiming success.
- Integer division by zero on a desktop target is runtime error 200, as in FPC.
  On ESP it gives 0 and the program continues, by design.

### Nil Python

Nil Python is Python-ish and known to have plenty of issues. Its measured list
is kept in one place, [Known limits](../targets/nil-python.md#known-limits) on the
Nil Python page. That list includes silent wrong answers. For example, an `-> int` result
wraps at 64 bits, and `hex()` of an int wider than 64 bits is wrong (both
confirmed on v423). The same page records the deliberate differences from
CPython; a difference not recorded there is a bug.

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
