# Targets & binaries

PXX is a self-contained compiler **and** assembler **and** linker: it emits a
finished executable directly. There is no external `as`, `ld`, or libc in the
pipeline, and no `execve` of any tool.

## Output format

By default a program that imports no shared objects compiles to a **static,
syscall-only ELF**: it talks to the kernel directly and links **no libc and no
dynamic loader**. So it runs on any Linux of the right architecture regardless
of distro or libc — no AppImage/snap/flatpak.

A program *may* still use shared libraries: an `external 'lib.so'` binding pulls
in that `.so` and the resulting binary is then **dynamically linked** for those
symbols (never through libc). Dynamic linking is currently an **x86-64**
capability; the cross targets emit static syscall-only binaries only.

## Cross-compilation

Pick the target with `--target=`:

| `--target=` | CPU | Pointer size | Status |
| --- | --- | --- | --- |
| `x86_64` (default) | AMD64 | 8 | primary |
| `i386` | 32-bit x86 | 4 | self-host byte-identical |
| `aarch64` | ARM64 | 8 | self-host byte-identical |
| `arm32` | 32-bit ARM | 4 | self-host byte-identical |
| `riscv32` | RV32 | 4 | codegen (bare-metal/embedded) |
| `xtensa` | ESP32 LX6/LX7 | 4 | codegen (bare-metal/embedded) |

The compiler **cross-compiles itself** to i386, aarch64, and arm32
byte-identically (`make cross-bootstrap`). The Linux targets above produce
runnable ELF binaries; `riscv32`/`xtensa` target embedded/bare-metal use.

`xtensa` accepts `--xtensa-abi=` for the call ABI variant.

To run a cross binary on an x86-64 host, use QEMU user-mode emulation; the repo
wraps this in `tools/run_target.sh <arch> <binary> [args…]`.

## Predefined conditional symbols

`PasInitDefines` seeds host symbols; once `--target` is known they are swapped
to match the target, so `{$ifdef CPU…}` branches see the *target*:

- Always: `PXX`, `LINUX`, `PXX_MANAGED_STRING` (managed strings — see
  [Types](types.md)).
- x86-64: `CPU64`, `CPUX86_64`.
- aarch64: `CPU64`, `CPUAARCH64`, `CPU_AARCH64`.
- arm32: `CPU32`, `CPUARM`, `CPU_ARM32`.
- i386: `CPU32`, `CPUI386`, `CPU_I386`.

`PXX` is built in and **cannot be undefined**. `{$ifdef FPC}` is reserved for
real Free Pascal and is always false under PXX — so source can branch
`{$ifdef FPC} … {$else} … {$endif}` to keep FPC and PXX both happy.

## Object output

`--emit-obj` writes a relocatable object instead of an executable (early/partial;
treat as unstable).
