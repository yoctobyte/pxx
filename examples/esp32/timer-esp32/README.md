# PXX classic-ESP32 `esptimer` demo (Xtensa LX6 / windowed)

`examples/esp32/timer-c3` and `examples/esp32/timer-s3` compiled for the third
chip. The source is byte-identical to both except for the program name: the
point is that the event surface (`TimerInit` / `OnElapsed` /
`TimerStartPeriodicMs`) and a callback taken with `@` are ABI-portable —
nothing in `main.pas` knows which chip it is on, across two ISAs and three
memory maps.

```sh
. ~/esp/esp-idf/export.sh
cd examples/esp32/timer-esp32
./build.sh                  # or ./build.sh qemu-assert
```

On real silicon, from the repo root:

```sh
tools/esp_flash.sh --project examples/esp32/timer-esp32 --port /dev/ttyUSB0
```

Expected serial output after the IDF banner:

```text
PXX timer: started
PXX timer: tick=1
...
PXX timer: tick=5
PXX timer: done ticks=5 status=0
```

**Board output, not re-measured on v450.** Last measured 2026-09-28 on an ESP32-D0WD-V3 with
compiler `b2b325036c3b` (pin v448): the board output matched `main.expected`,
7 lines (LOGBOOK, 2026-09-28).

`status` is a bitmask the program builds itself — 1 = start failed, 2 = fewer
than five ticks arrived, 4 = stop failed — so `status=0` cannot be printed by a
dead timer. That matters here because this whole example family exists to guard
a bug that printed plausible-looking output: a 64-bit argument passed with only
its low word sent `esp_timer_start_periodic` a period with a stale pointer in
its high half, setting the alarm some 145,000 years out
(`devdocs/progress/done/bug-esp-timer-callback-never-dispatched.md`).

Checked on 2026-09-29 with v451 (compiler sha256 `d9b7226769cc`) from the release archive, under Espressif's QEMU, not on a board: `./build.sh qemu-assert` ended with `OK   timer-esp32 qemu acceptance -- 5 esp_timer callbacks on an emulated LX6, status=0` after about 4 minutes.

## What differs from `timer-s3`, and why

Only the build script, and only in three places:

- **`--target=esp32`, the chip name, not `--target=xtensa --xtensa-abi=windowed`.**
  The generic xtensa spelling answers the S3's memory map; this is an LX6. The
  chip name implies the windowed ABI on the IDF platform, so the separate
  `--xtensa-abi` is redundant. Same reasoning as `hello-esp32`.
- **`xtensa-esp32-elf-ar`**, not `xtensa-esp32s3-elf-ar`.
- **QEMU is `-M esp32` with no `-m 32M`.** One `qemu-system-xtensa` serves both
  chips (`-machine help` lists `esp32` and `esp32s3`); only the machine changes.
  The S3's IDF entry carries `-m 32M` and the C3's does not — the classic ESP32
  takes at most 4MB of external PSRAM and QEMU's `esp32` machine sets its own
  default, so forcing 32M would describe a machine that does not exist.

The Pascal source, both `CMakeLists.txt` files and the `REQUIRES esp_timer`
wiring are unchanged from `timer-s3`.

## Scope

The owner's settled ESP scope is the **S3 and C3**. The classic ESP32 is
**proven where run, not promised**: this example is here because it was run, and
the chip it was verified on is stated with its result rather than implied. See
`docs/library/esp.md` for the per-unit table of what has actually been witnessed
on which chip.
