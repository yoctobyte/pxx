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

## ESP32 chips, boards, and ISA strategy

Two of PXX's cross targets cover the ESP32 family, split by instruction set:

| Chip | ISA | PXX `--target` | Notes |
| --- | --- | --- | --- |
| ESP32 (orig) | Xtensa LX6 | `xtensa` (`--xtensa-cpu=lx6`) | dual-core |
| ESP32-S2 | Xtensa LX7 | `xtensa` | single-core |
| ESP32-S3 | Xtensa LX7 | `xtensa` | dual-core |
| ESP32-C3 | RISC-V RV32IMC | `riscv32` | cheap, single-core; common baseline |
| ESP32-C6 | RISC-V RV32IMAC | `riscv32` | + Wi-Fi 6 / 802.15.4 vs C3; same PXX codegen |
| ESP32-P4 / future C/S parts | RISC-V | `riscv32` | Espressif's stated direction |

**Boards vs chips.** Board form factors (DevKitC, DevKitM, "Mini", Super-Mini,
nano clones, …) are just carrier boards — the target is chosen by the **chip**,
not the board. Any S3 board uses `--target=xtensa`; any C3/C6 board uses
`--target=riscv32`.

**ISA direction.** Espressif is steering new silicon to RISC-V (the C-series,
P4, and a coming RISC-V S-class part). So **`riscv32` is the long-term ESP
target**; Xtensa is effectively legacy. We do **not** drop Xtensa, though:

- S2/S3 hardware is owned and in active use here.
- Older/cheaper parts (C3, S2, original ESP32) stay adequate for many projects
  and remain on shelves for years.

Practical stance: keep both ISAs working, but put new ESP effort on the RISC-V
(`riscv32`) path first; treat Xtensa as feature-frozen-plus-fixes. The
difference between, e.g., C3 and C6 is mostly the radio and peripherals — not the
PXX codegen, which is the same `riscv32` backend for both.

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
