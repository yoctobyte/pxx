# Compile target: ESP32 / embedded

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Blocked-by:** feature-target-arm32
- **Unblocks:** feature-additional-cpu-targets
- **Opened:** 2026-06-06 (user request; roadmap.md Phase 5)

## Motivation

The embedded milestone has two useful faces:

- **ESP-IDF integration:** use Espressif's supported SDK/toolchain/build flow so
  PXX programs can run on real ESP32 boards and call Wi-Fi, networking, NVS,
  GPIO, timers, FreeRTOS, and other vendor APIs without reimplementing the SDK.
  This is the practical path for hardware already on the shelf, especially
  ESP32-S2/S3 Xtensa boards.
- **Bare-metal profile:** own startup, memory policy, image/link path, UART/GPIO,
  and allocator without depending on ESP-IDF. This remains useful for compiler
  control, tiny firmware, and later RISC-V ESP32-C3-class work.

The key decision is to treat ESP-IDF as an explicit target profile, not as the
compiler's identity. `target esp32-idf` may depend on Espressif tooling;
`target esp32-bare` does not.

## Scope

Per `../../developer/roadmap.md` Phase 5 and
`../../developer/esp32-esp-idf-roadmap.md`, split the work into two profiles:

### `esp32-idf`

- Automate an ESP-IDF project/component wrapper around PXX output.
- Pin an ESP-IDF version and chip target for reproducibility.
- Start with ESP32-S2/S3 via Espressif's Xtensa toolchain because that is the
  available shelf hardware and lets IDF own the difficult boot/link/image/SDK
  pieces.
- First integration may use generated C or an IDF-compiled bridge if that gets a
  working board loop fastest. Native object/archive emission can follow.
- Provide an `app_main` bridge into a PXX entrypoint.
- Import selected ESP-IDF C headers directly, beginning with GPIO/UART and
  FreeRTOS delay/task APIs; later NVS, lwIP, Wi-Fi, BLE, etc.
- Let `idf.py` own sdkconfig, component dependency resolution, linker script
  generation, bootloader, partition table, ELF link, `elf2image`, flash, and
  monitor.

### `esp32-bare`

- Prefer ESP32-C3/RISC-V for the first compiler-owned path because the ISA and
  ABI are cleaner than Xtensa.
- Bare-metal output format: no Linux ELF/syscalls; linker-defined RAM regions;
  startup without an OS.
- Minimal hardware scope first: UART hello and GPIO toggle.
- Depends on the static-arena allocator profile (no host syscalls) —
  `feature-static-arena-profile`.

## Acceptance

- `target esp32-idf` can build and flash a minimal PXX program on an ESP32-S2 or
  ESP32-S3 board through an automated ESP-IDF wrapper.
- First IDF demo toggles GPIO and uses a FreeRTOS delay/task API from imported
  or declared ESP-IDF C bindings.
- The user-facing command hides the generated IDF project mechanics as much as
  practical.
- `target esp32-bare` remains a separate milestone: minimal UART/GPIO on
  ESP32-C3/RISC-V or emulator, exercising the syscall-free runtime profile and
  compiler-owned image/startup path.

## Testing strategy

Testing remains central. Emulate everything that exercises the compiler's side
of the contract, and keep real hardware tests focused on places where emulation
cannot prove the result.

- **Pure host tests:** parser, C importer, generated bindings, Pascal/Nil
  runtime pieces, IDF wrapper generation, and sdkconfig/project skeleton
  generation.
- **Cross backend tests:** validate generated CPU code under QEMU where possible
  for ISA/ABI behavior, calls, stack layout, data layout, arithmetic, globals,
  and runtime helpers. Upstream QEMU is enough for generic RISC-V backend
  coverage; Espressif QEMU is useful for ESP chip startup/peripheral smoke.
- **IDF build tests:** generated `esp32-idf` projects compile for pinned
  ESP-IDF/chip configurations. This catches stale project generation,
  component dependencies, C bridge breakage, header import drift, and linker
  integration mistakes.
- **IDF QEMU smoke tests:** use Espressif QEMU / `idf.py qemu monitor` where
  available to boot the generated app, assert known UART output, and exercise
  FreeRTOS delay/task sanity without flashing every edit.
- **Hardware smoke tests:** keep a small board-backed suite for behavior
  emulation cannot credibly prove: GPIO timing, flash/NVS, Wi-Fi/BLE, reset/boot
  behavior, USB/serial/JTAG quirks, and radio/network integration.

Trust Espressif libraries to do the right thing on real hardware once the call
contract is correct. The bugs to hunt in this repo are mostly: wrong ABI,
incorrect stack alignment, bad struct/enum/imported type mapping, bad
string/pointer lifetimes across C calls, incorrect callback signatures, Pascal
runtime assumptions that clash with FreeRTOS/IDF memory or threading, generated
IDF config drift, and missed initialization order such as NVS before Wi-Fi.

First test target:

```text
build generated IDF project -> run in QEMU or flash -> serial contains
"PXX hello" -> GPIO blink loop starts -> FreeRTOS delay is used
```

## Dependency note

`Blocked-by feature-target-arm32` is roadmap staging; the harder real prerequisite
for bare metal is the static-arena profile and bare-metal runtime, not ARM32
specifically. The `esp32-idf` path can be pulled forward independently because
IDF provides the platform runtime and build/image machinery.

## Log
- 2026-06-06 — ticket opened from user request + roadmap Phase 5.
- 2026-06-10 — scope decision with user (churn defense): target the ISA, not
  the ecosystem. Espressif churns chips ~6-monthly but stopped churning ISAs:
  everything new (C2/C3/C6/H2/P4) is RISC-V RV32IMC-class. So: (1) skip
  Xtensa entirely (classic ESP32/S2/S3 — dead end, Espressif migrating off);
  (2) one RV32IMC backend covers the whole forward roadmap; (3) pin ESP32-C3
  as reference chip — chip-specific surface is just boot image header + ROM
  UART, stable per family; (4) scope fence: NO radio, NO ESP-IDF in v1 —
  that is where the churn lives; acceptance = bare-metal UART hello + GPIO.
  WiFi/BLE later as deliberate version-pinned IDF interop (net_esp32).
  Testing: upstream qemu riscv32 'virt' proves ISA codegen (already in
  tools/run_target.sh); Espressif's qemu fork has ESP32-C3 system emulation
  for the chip-level step.
- 2026-06-11 — revised with user after ESP-IDF/FreeRTOS discussion and actual
  hardware inventory. Do not skip Xtensa for the practical IDF path: user has
  ESP32-S2/S3 boards. Use Espressif's toolchain/build system when the goal is
  Wi-Fi/networking/vendor drivers, because IDF already bundles startup,
  FreeRTOS, linker placement, bootloader/image generation, partitioning, NVS,
  lwIP, and device support. Keep compiler-owned RISC-V bare metal as a separate
  profile instead of blocking useful ESP32 work on SDK replacement.
