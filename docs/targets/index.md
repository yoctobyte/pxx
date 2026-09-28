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
`esp32c3`, `esp32c6`, `esp32h2` and `esp32p4` are riscv32. Pin v445 compiles
an ESP-IDF object for every one of these names (re-checked 2026-09-27). The bare-metal profile supports
only `esp32s3` and `esp32c3`, and says so for the others. It runs under QEMU
only; on a real board use the ESP-IDF profile (see
[known issues](../reference/known-issues.md)). The ESP32-S3 and the
ESP32-C3 have been run on physical boards (with the ESP-IDF profile); the
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

Measured with **pin v445** (compiler sha256 `caf21ac399f1…`) on 2026-09-27;
every cell is the same as with v425. Programs other than x86-64 ones were run
under QEMU user mode, and wasm32 under wasmtime; none of the Linux cross
targets was run on real hardware for this table. The probes: a class with an
exception caught and a line written; `writeln(SizeOf(Real))`;
`test/lib_classes_tthread.pas` and `test/c_pthread_detach.c`; a `threadvar`
set and read; `--emit-obj` on `test/c_obj_data_export.c`; `--shared` on
`test/test_library_exports.pas`; a Nil Python `sum` of a list; and C's
`sqrt(2.0)`.

| | x86-64 | i386 | aarch64 | arm32 | riscv32 Linux | wasm32 |
| --- | --- | --- | --- | --- | --- | --- |
| Pascal classes, exceptions, console I/O | yes | yes | yes | yes | yes | yes |
| `SizeOf(Real)` | 8 | 8 | 8 | 8 | 4 | 8 |
| Threads (`TThread`, C `pthread_create`) with `--threadsafe` | yes | yes | yes | yes | refused | refused |
| Pascal `threadvar` | yes | yes (from v446) | yes | yes | refused | refused |
| `--emit-obj` (relocatable object) | yes | yes | yes | yes | yes | refused |
| `--shared` (shared library) | yes | refused | refused | refused | refused | refused |
| Nil Python | yes | yes | yes | yes | refused | yes |
| C with `#include <math.h>` | yes | yes | yes | yes | yes | yes |

Compared with v424, one cell changed: wasm32 C with `math.h` was refused
there. **Pascal `threadvar` on i386 is refused with v445 and works from
v446** (`7dc976a8cc`, which also gives each i386 thread its own C `__thread`
copies). On 2026-09-28, the two thread rows were measured again with pin v446
(`ae3466a018d8`) and with the compiler at `e072d579b0`, under QEMU: each
thread kept its own `threadvar` and `__thread` values on x86-64, i386,
aarch64 and arm32. See [Threads & parallelism](../library/concurrency.md#targets).

Every **refused** cell is a compile-time error that names the reason; none
produces a program that runs wrongly. Most messages say in plain words what is
unsupported, for example `--threadsafe is available for x86-64, i386, aarch64
and arm32 only; it is refused for riscv32.` and, for every target but x86-64,
`--shared: shared-library output is x86-64 only`. `xtensa` also has an object
writer; it is the ESP-IDF route.

## Pages

- [Cross-compilation](./cross-compilation.md)
- [Cross languages](./cross-languages.md)
- [C Frontend](./c-frontend.md)
- [Nil Python](./nil-python.md)
- [Other frontends](./other-frontends.md)

## Next

- [Command-line reference](../reference/cli.md)
