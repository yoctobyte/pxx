---
title: Targets
order: 60
---

# Targets

PXX can emit native and cross-target output from the same compiler invocation.

## Supported target names

| Target | Main use |
| --- | --- |
| `x86_64` | Native Linux executable output on x86-64. |
| `i386` | 32-bit Linux ELF output. |
| `aarch64` | 64-bit ARM Linux ELF output. |
| `arm32` | 32-bit ARM Linux ELF output. |
| `riscv32` | ESP32-C3 / embedded RISC-V output. |
| `xtensa` | ESP32-S2/S3 / embedded Xtensa output. |

Use `--target=ARCH` before the source file:

```sh
./pxx --target=aarch64 hello.pas hello.a64
```

## Pages

- [Cross-compilation](./cross-compilation.md)
- [Cross languages](./cross-languages.md)

## Next

- [Command-line reference](../reference/cli.md)
