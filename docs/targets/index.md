---
title: Targets
order: 60
---

# Targets

PXX can emit native and cross-target output from the same compiler invocation.

## Supported target names

| Target | Output | Typical run path |
| --- | --- | --- |
| `x86_64` | Native Linux ELF executable. | Run directly on x86-64 Linux. |
| `i386` | 32-bit Linux ELF executable. | Run directly on hosts with i386 support, or via `qemu-i386`. |
| `aarch64` | 64-bit ARM Linux ELF executable. | Run via `qemu-aarch64` on non-ARM hosts. |
| `arm32` | 32-bit ARM Linux ELF executable. | Run via `qemu-arm` on non-ARM hosts. |
| `riscv32` | ESP32-C3 bare-metal / ESP-IDF object, or 32-bit RISC-V Linux ELF. | See [ESP32 / Microcontrollers](./esp32.md); Linux binaries run via `qemu-riscv32`. |
| `xtensa` | ESP32-S2/S3 bare-metal / ESP-IDF object. | See [ESP32 / Microcontrollers](./esp32.md). |

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
`examples/esp32/`.

## Pages

- [Cross-compilation](./cross-compilation.md)
- [Cross languages](./cross-languages.md)
- [C Frontend](./c-frontend.md)
- [Nil Python](./nil-python.md)

## Next

- [Command-line reference](../reference/cli.md)
