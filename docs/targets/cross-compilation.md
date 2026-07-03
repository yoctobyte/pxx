---
title: Cross-compilation
order: 61
---

# Cross-compilation

Pass `--target=` to select a non-default CPU target:

```sh
./pxx --target=i386 hello.pas hello.i386
./pxx --target=aarch64 hello.pas hello.a64
./pxx --target=arm32 hello.pas hello.arm
```

Linux cross-target executables can be run with QEMU user-mode when the matching
runtime support is installed. Install the QEMU runners if needed:

```sh
tools/install_qemu.sh
```

Then run through the repository helper:

```sh
tools/run_target.sh aarch64 ./hello.a64
tools/run_target.sh arm32 ./hello.arm
```

Static syscall-only PXX binaries do not need a target sysroot for normal
cross-target smoke runs. Binaries that deliberately use external C libraries may
need a guest dynamic loader and libc; `tools/run_target.sh` honors
`QEMU_LD_PREFIX` and `PXX_CROSS_SYSROOT` for those cases.

ESP32 flows use target-specific helpers and may require vendor tooling:

```sh
tools/esp_run_bare.sh --chip esp32c3 examples/esp32/hello-c3/main/main.pas
tools/esp_run_bare.sh --chip esp32s3 examples/esp32/hello-s3/main/main.pas
```

See [ESP32 / Microcontrollers](./esp32.md) for the bare-metal and ESP-IDF
integration modes, footprint numbers, and the soft-float contract.

Hosted 32-bit RISC-V Linux is also a full target: plain
`--target=riscv32` (without `--esp-profile=bare`) emits a Linux ELF that
runs under `qemu-riscv32`, with console I/O, exceptions, classes and the
rest of the shared-IR surface.

## Next

- [Targets](./)
- [Command-line reference](../reference/cli.md)
