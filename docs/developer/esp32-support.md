# ESP32 Support Setup

This note records the practical ESP32 support model for PXX and the host tools
needed to build and test it.

## Target profiles

PXX should treat ESP32 as two explicit target profiles:

- `esp32-idf`: use Espressif's ESP-IDF SDK, build system, toolchain, FreeRTOS
  integration, bootloader, partition handling, linker scripts, image generation,
  flash/monitor tooling, and vendor libraries. This is the practical profile for
  ESP32-S2/S3 Xtensa boards and anything involving Wi-Fi, BLE, lwIP, NVS,
  filesystems, or rich peripheral drivers.
- `esp32-bare`: own startup, memory policy, image/link path, UART/GPIO, and the
  allocator without depending on ESP-IDF. This profile is useful for compiler
  control and tiny firmware. Prefer ESP32-C3/RISC-V for the first compiler-owned
  path because the ISA and ABI are cleaner than Xtensa.

The compiler remains independent. The IDF dependency is a platform backend
dependency, not the identity of the compiler.

## ISA baseline

The ESP backends emit native hardware opcodes for a modern-part baseline,
matching the Espressif gcc toolchains: **Xtensa = ESP32-S2/S3 (LX7) and
later** (32-bit multiply + divide options: `mull`, `quos`/`rems`, SAR
shifts); **RISC-V = ESP32-C3 and later** (RV32IMC, `mul`/`div`/`rem`). These
are the user's boards. Software fallbacks for ESP32-classic (LX6, no divide
option) and similar are deferred — see
`docs/progress/backlog/feature-esp-isa-baseline-softfallback.md`.

## Managed-feature spine (2026-06-17)

Well beyond stage 1: the managed-runtime spine runs on **both** ESP ISAs,
validated on Espressif QEMU against the x86-64 oracle (see
`docs/progress/done/feature-esp32-managed-features.md`). Output-equality harness
`tools/esp_run.sh [--chip esp32s3|esp32c3] <prog.pas>` (needs
`. ~/esp/esp-idf/export.sh`; heavy, not in `make test`). Working: native
div/mod + shifts, the xtensa windowed-ABI constant-sp fix (nested/recursive
calls), static-arena heap (New/GetMem/Dispose), dynamic arrays
(SetLength/Length/index), `array of const` → portable writeln, and
Ord/Chr/Integer/LongWord passthroughs. Not yet ported: **managed strings**
(`tyAnsiString` `PXXStr*` runtime — the PXX default; see
`feature-esp32-managed-strings`), records-by-value, classes/VMT, sets,
exceptions, RTTI.

## Bare-metal boot (2026-06-18, esp32c3)

The `esp32-bare` profile now boots a self-contained image with **no ESP-IDF** —
no FreeRTOS, no second-stage bootloader, no `esp_rom_printf`. Enable it with
`--esp-profile=bare`: `--target=riscv32` (ESP32-C3) or `--target=xtensa`
(ESP32-S3, Call0 only).

How it works:

- **Image / load path.** `writeELF32` links a linked `ET_EXEC` at the SoC SRAM
  map instead of the Linux base: `ESP_BARE_IRAM_BASE = 0x40380000` on C3 (the
  instruction-bus SRAM org past the 16 KiB ICache) / `0x40378000` on S3 (the
  shared I/D SRAM org). The internal SRAM is mapped twice (C3: IRAM
  `0x4037C000`, DRAM `0x3FC7C000`); qemu models it as one RWX region, so the
  whole image (code + data + bss) plus the stack live in that single window — no
  separate IRAM/DRAM segments needed. Espressif QEMU loads the raw ELF directly
  with `-kernel` (it honors the program-header load address and sets `pc` to the
  ELF entry — no flash image / `esptool merge-bin` / second-stage header).
- **Startup.** No kernel set up a stack, so the entry stub establishes `sp` at
  the top of SRAM (`ESP_BARE_STACK_TOP = 0x403C0000`, valid IRAM on both C3 and
  S3, grows down toward the image) before jumping to `main`: RISC-V via
  `lui`/`addi`, Xtensa via an `l32r` literal-island load into `a1`. BSS is
  zero-filled by the loader (`memsz > filesz`).
- **Xtensa is Call0-only on bare metal.** The windowed ABI's `entry`/`retw`
  raise window overflow/underflow exceptions that need handlers installed at
  `vecbase`; bare metal installs none. Call0 has no register windows, so it
  needs no exception handlers and no `vecbase`/`PS` setup — `--esp-profile=bare`
  rejects `--xtensa-abi=windowed`.
- **Output.** No ROM printf — the program writes bytes straight to the UART0
  transmit FIFO, MMIO at `0x60000000` (both SoCs) via
  `PByte(Int64($60000000))^ := b`. The static-arena heap and managed
  `AnsiString` work unchanged on bare metal, both ISAs.

Run + validate (no IDF needed, just the Espressif qemu forks):

```bash
tools/esp_run_bare.sh --chip esp32c3 test/test_esp_bare.pas   # riscv32, raw UART bytes
tools/esp_run_bare.sh --chip esp32s3 test/test_esp_bare.pas   # xtensa Call0
make test-esp-bare                                            # both, diff vs x86-64 oracle
```

`test/test_esp_bare.pas` prints a string + signed integers; the bytes match the
x86-64 oracle exactly on both chips. A frame-pointer (`s0`) stack walk was
confirmed in `riscv32-esp-elf-gdb` against the C3 bare image: the prologue saves
the caller frame pointer at `[s0+8]` and the return address at `[s0+12]`, and
chasing that chain from a deep recursion unwinds cleanly through every frame
back to `main` (fp terminates at 0). NB: this qemu `gdbstub` does not honor
breakpoints (`continue` hangs) but `stepi` works — step to the target pc, then
walk `s0`. (Xtensa Call0 keeps no dedicated frame pointer, so the riscv32 walk
is the canonical fp-unwind proof.)

## Current state (2026-06-12)

Stage 1 (bare codegen) and the relocatable object writer are done:

- `--target=riscv32` and `--target=xtensa` compile the stage-1 language
  subset (procs/params/calls/loops/ifs/globals) through the IR path; both
  smoke binaries execute correctly under user-mode QEMU
  (`docs/progress/done/feature-target-esp32.md`).
- `--emit-obj` (or a `.o` output path) produces an ET_REL ELF32 object for
  either target (`writeELF32Rel` in `compiler/elfwriter.inc`;
  `docs/progress/done/feature-elf-rel-writer.md`). Every absolute address
  goes through a 32-bit literal slot, so all relocations are plain
  `R_XTENSA_32` / `R_RISCV_32` data words — no code relocations and no
  linker-relaxation interaction. Every proc is a local `FUNC` symbol, the
  program entry is exported globally as `app_main`, and `external`
  procedure declarations become undefined symbols called indirectly through
  a relocated literal slot.
- Regression: `make test-emit-obj` (readelf checks always; link checks when
  the ESP toolchains are installed under `~/.espressif`).
- Host prerequisites verified 2026-06-12: flex/bison/gperf/ccache/dfu-util/
  cmake/ninja/libusb installed, `idf.py --version` reports ESP-IDF v6.0.1
  after `export.sh`, and Espressif `qemu-system-riscv32` 9.2.2 provides the
  `esp32c3` machine. Nothing blocks `idf.py build` for the
  `feature-esp32-idf-riscv32` ticket.

Link recipe against a C shim (acceptance check, not the IDF flow yet):

```bash
./compiler/pascal26 --target=riscv32 prog.pas prog.o
riscv32-esp-elf-gcc -nostartfiles -Wl,-e,app_main shim.c prog.o -o prog.elf
```

ESP-IDF integration is proven on ESP32-C3 (2026-06-12): see
`examples/esp32/hello-c3` — Pascal `app_main` linked by `idf.py build` and
booted under Espressif QEMU, printing from a Pascal loop via
`esp_rom_printf`. PXX `app_main` never returns (bare-metal self-loop), so
the example parks in a terminal `vTaskDelay` loop; a returning epilogue
remains future work. Xtensa S2/S3 needs the windowed-ABI ticket.

## What ESP-IDF provides

ESP-IDF is not just a compiler package. For normal ESP32 development it provides:

- chip startup and C runtime setup;
- Espressif's FreeRTOS integration;
- sdkconfig/Kconfig configuration;
- component dependency resolution;
- generated linker scripts and placement rules for flash, IRAM, DRAM, RTC, etc.;
- bootloader and partition table handling;
- ELF link, ESP app image conversion, flash, and monitor commands;
- vendor libraries such as GPIO/UART/SPI/I2C drivers, Wi-Fi, BLE, lwIP, NVS,
  logging, heap capabilities, timers, and event loop support.

That is why `esp32-idf` should interoperate with ESP-IDF instead of replacing it
at first. Replacing the linker/image/build path can be revisited only after the
IDF integration path is understood and testable.

## Host install buckets

There are three separate tool groups:

- **System packages:** Python, Git, CMake, Ninja, USB tools, normal QEMU
  user-mode emulators.
- **ESP-IDF checkout and managed tools:** a pinned ESP-IDF Git checkout plus
  Espressif-installed cross compilers, GDB/OpenOCD/esptool support, Python
  environment, etc. These are version-specific and should not be assumed to come
  from the OS package manager.
- **Espressif QEMU:** Espressif's QEMU fork for chip-level IDF smoke tests,
  installed through `idf_tools.py`, separate from distro `qemu-user`.

For Debian/Ubuntu-like hosts, the useful system package set is:

```bash
sudo apt-get install -y \
  git wget flex bison gperf \
  python3 python3-pip python3-venv \
  cmake ninja-build ccache \
  libffi-dev libssl-dev \
  dfu-util libusb-1.0-0 \
  libgcrypt20 libglib2.0-0 libpixman-1-0 libsdl2-2.0-0 libslirp0 \
  qemu-user qemu-user-static binfmt-support
```

The current Linux cross-target tests use normal QEMU user-mode emulators:

```bash
tools/install_qemu.sh
make qemu-env-check
```

That covers `qemu-i386`, `qemu-aarch64`, `qemu-arm`, `qemu-riscv32`, and
`qemu-riscv64` for static Linux-target test binaries. It does not replace
Espressif QEMU for ESP-IDF app startup tests.

## Installer

Use the repo installer for the ESP32/ESP-IDF toolchain:

```bash
tools/install_esp32_target.sh
```

Defaults:

- ESP-IDF directory: `$HOME/esp/esp-idf`
- ESP-IDF version: `v6.0.1`
- IDF targets: `esp32s2,esp32s3`
- Espressif QEMU tools: `qemu-xtensa qemu-riscv32`

Override with environment variables:

```bash
ESP_IDF_DIR=$HOME/esp/esp-idf-v6 \
ESP_IDF_VERSION=v6.0.1 \
ESP_IDF_TARGETS=esp32s2,esp32s3 \
ESP_IDF_QEMU_TOOLS="qemu-xtensa qemu-riscv32" \
tools/install_esp32_target.sh
```

After installation, load the ESP-IDF environment in each shell that should use
`idf.py`:

```bash
. "$HOME/esp/esp-idf/export.sh"
idf.py --version
```

A child installer cannot permanently modify the parent shell environment, so the
explicit `export.sh` step is still required for interactive use.

## Testing ladder

Emulate everything that exercises PXX's side of the contract:

- parser/importer/runtime tests on the host;
- generated binding and IDF wrapper generation tests;
- backend and ABI tests under QEMU where possible;
- generated ESP-IDF project build tests for pinned chip/version combinations;
- Espressif QEMU smoke tests with `idf.py qemu monitor` where available.

Keep hardware tests small and focused on behavior emulation cannot credibly
prove: GPIO timing, flash/NVS, Wi-Fi/BLE, reset/boot behavior, USB/serial/JTAG
quirks, and radio/network integration.

The first useful `esp32-idf` smoke target is:

```text
build generated IDF project -> run in QEMU or flash -> serial contains
"PXX hello" -> GPIO blink loop starts -> FreeRTOS delay is used
```

Trust Espressif libraries to do the right thing on real hardware once PXX gets
the ABI, config, initialization order, and lifetime rules right. The bugs to
hunt here are mostly ours: wrong ABI, bad stack alignment, bad imported type
mapping, pointer/string lifetime mistakes, callback signature errors, Pascal
runtime assumptions that clash with FreeRTOS/IDF memory or threading, generated
config drift, and missed initialization such as NVS before Wi-Fi.

## References

- ESP-IDF downloadable tools:
  <https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-guides/tools/idf-tools.html>
- ESP-IDF QEMU:
  <https://docs.espressif.com/projects/esp-idf/en/stable/esp32s3/api-guides/tools/qemu.html>
- ESP-IDF Docker image:
  <https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-guides/tools/idf-docker-image.html>
