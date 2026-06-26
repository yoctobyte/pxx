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
runtime support is installed. The repository helper is:

```sh
tools/run_target.sh aarch64 ./hello.a64
```

ESP32 flows use target-specific helpers and may require vendor tooling:

```sh
tools/esp_run_bare.sh --chip esp32c3 examples/esp32/hello-c3/main/main.pas
tools/esp_run_bare.sh --chip esp32s3 examples/esp32/hello-s3/main/main.pas
```

The ESP32 path is under active development. Treat it as an embedded bring-up
surface rather than a general-purpose stable release target.

## Next

- [Targets](./)
- [Command-line reference](../reference/cli.md)
