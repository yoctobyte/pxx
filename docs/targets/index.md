---
title: Targets
order: 60
---

# Targets

PXX can emit native and cross-target output from the same compiler invocation.

## Supported target names

| Target | Output | Typical run path |
| --- | --- | --- |
| `x86_64` | Native Linux ELF executable (the default). | Run directly on x86-64 Linux. |
| `i386` | 32-bit Linux ELF executable. | Run directly on hosts with i386 support, or via `qemu-i386`. |
| `aarch64` | 64-bit ARM Linux ELF executable. | Run via `qemu-aarch64` on non-ARM hosts. |
| `arm32` | 32-bit ARM Linux ELF executable. | Run via `qemu-arm` on non-ARM hosts. |
| `riscv32` | 32-bit RISC-V Linux ELF, or an ESP32-C3 object or bare-metal image. | Linux binaries run via `qemu-riscv32`; for ESP see [ESP32](./esp32.md). |
| `xtensa` | ESP32-S2/S3 object or bare-metal image. | See [ESP32](./esp32.md). |
| `wasm32` | WebAssembly module. | Run with `wasmtime`. |

`pxx --list-targets` prints this list for your build. From pin v425 it
describes wasm32 as `via wasmtime` for Pascal, C and Nil Python; v424 wrongly
said "registered only — no codegen yet". The table below shows what wasm32
actually does.

ESP chip names are accepted as targets too. They imply the CPU and
`--platform=esp`: `esp32`, `esp32s2` and `esp32s3` are xtensa; `esp32c2`,
`esp32c3`, `esp32c6`, `esp32h2` and `esp32p4` are riscv32. v424 compiles an
ESP-IDF object for every one of these names. The bare-metal profile supports
only `esp32s3` and `esp32c3`, and says so for the others. It runs under QEMU
only; on a real board use the ESP-IDF profile (see
[known issues](../reference/known-issues.md)). Only the ESP32-S3
has been run on a physical board; the ESP32-C3 has been run under QEMU; the
rest have only been compiled.

Use `--target=ARCH` before the source file:

```sh
./pxx --target=aarch64 hello.pas hello.a64
```

For Linux cross-target executables, `tools/run_target.sh` chooses the right QEMU
user-mode runner when the host cannot execute the file directly.

```sh
tools/run_target.sh aarch64 ./hello.a64
```

For ESP32 targets, start with the board-specific examples under
`examples/esp32/`; the peripheral units are in
[ESP32 peripherals](../library/esp.md).

## What each target supports

Measured with **pin v424** (compiler sha256 `93a336a7ba85…`) on 2026-09-25,
the previous pin. The `math.h` row and the refusal messages below were
re-checked with **pin v425** (compiler sha256 `426b2fbf3f08…`) the same day.
Programs other than x86-64 ones were run under QEMU user mode, and wasm32 under
wasmtime; none of the Linux cross targets was run on real hardware for this
table.

| | x86-64 | i386 | aarch64 | arm32 | riscv32 Linux | wasm32 |
| --- | --- | --- | --- | --- | --- | --- |
| Pascal classes, exceptions, console I/O | yes | yes | yes | yes | yes | yes |
| `SizeOf(Real)` | 8 | 8 | 8 | 8 | 4 | 8 |
| Threads (`TThread`, C `pthread_create`) with `--threadsafe` | yes | yes | yes | yes | refused | refused |
| Pascal `threadvar` | yes | refused | yes | yes | refused | refused |
| `--emit-obj` (relocatable object) | yes | yes | yes | yes | yes | refused |
| `--shared` (shared library) | yes | refused | refused | refused | refused | refused |
| Nil Python | yes | yes | yes | yes | refused | yes |
| C with `#include <math.h>` | yes | yes | yes | yes | yes | yes (refused in v424) |

Every **refused** cell is a compile-time error that names the reason; none
produces a program that runs wrongly. From v425 each message says in plain
words what is unsupported, for example `--threadsafe is available for x86-64,
i386, aarch64 and arm32 only; it is refused for riscv32.` On v424, three of them
were worded for compiler developers: `--shared` on aarch64 and arm32,
`--threadsafe` on riscv32 and wasm32, and Nil Python on riscv32
(`a heap arena needs mmap`). `xtensa` also has an object writer; it is the
ESP-IDF route.

## Pages

- [Cross-compilation](./cross-compilation.md)
- [Cross languages](./cross-languages.md)
- [C Frontend](./c-frontend.md)
- [Nil Python](./nil-python.md)
- [Other frontends](./other-frontends.md)

## Next

- [Command-line reference](../reference/cli.md)
