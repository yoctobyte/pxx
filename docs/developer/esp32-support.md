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

Link recipe against a C shim (acceptance check, not the IDF flow yet):

```bash
./compiler/pascal26 --target=riscv32 prog.pas prog.o
riscv32-esp-elf-gcc -nostartfiles -Wl,-e,app_main shim.c prog.o -o prog.elf
```

Known gap for the IDF profile: `app_main` currently never returns — the
bare-metal exit path parks in a self-loop. The `feature-esp32-idf-riscv32`
ticket owns the returning runtime epilogue and the real component link.

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
