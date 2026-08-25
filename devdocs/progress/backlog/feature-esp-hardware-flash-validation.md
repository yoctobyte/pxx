---
prio: 25
track: S
---

# ESP32 real-hardware flash + boot validation (S2/S3, C3)

- **Type:** feature (validation — requires physical hardware) — Track A
- **Status:** backlog (blocked on hardware access; un-automatable in-harness)
- **Opened:** 2026-06-30 (split from feature-esp32-idf-xtensa, whose QEMU scope is done)

## Scope

The ESP QEMU + GDB path is verified ([[feature-esp32-idf-xtensa]] done). What
remains can only be done with a board on USB:
- Flash a pxx-built ESP32-S2/S3 (Xtensa) + ESP32-C3 (riscv32) image to real silicon.
- Confirm UART boot output matches the QEMU/x86-64 oracle.
- Exercise a live ISR / peripheral (timer/GPIO) on hardware (the QEMU path can't
  install a real vector).

## Acceptance

A pxx ESP image boots on a physical board and its UART output matches the oracle;
a basic peripheral/ISR fires on hardware. Requires the user's board + USB access.


## Everything except the board is now in place (2026-08-02)

The three things that made this "un-automatable" are done; what is left is
literally plugging a board in.

### 1. One command flashes and checks

```sh
tools/esp_flash.sh [--chip esp32s2|esp32s3|esp32c3] [--port /dev/ttyUSB0] <prog.pas>
```

`tools/esp_flash.sh` is the silicon twin of `tools/esp_run.sh` — same projects,
same compiler flags, same output filter — so a program verified under qemu is
re-checked on hardware with one word changed. It compiles the program for the
chip, links it into the matching IDF project, writes flash with esptool, reads
the serial console for N seconds, and (by default) **diffs what the board said
against the same program run on x86-64**. It finds the port itself when exactly
one is present and refuses to guess between several.

### 2. A program worth running first

`test/test_esp_hw_validation.pas` — everything it prints is pure computation, so
board output must equal the x86-64 run byte for byte. It covers 64-bit
arithmetic, a by-value record result, a 9-word argument list (the two xtensa ABI
gaps closed this session), and managed strings; it toggles GPIO2 between lines
so an LED or a scope shows it is really executing.

Verified under qemu against the oracle on **esp32s3 (Xtensa/windowed)** and
**esp32c3 (riscv32)**. The S2 has no qemu machine, so its first run IS the
hardware run.

### 3. The S2 exists as a target at all

`examples/esp32/hello-s2` is new. The S2 was never built for before — every
project here was S3 or C3 — and it is half the user's hardware. It builds and
links a pxx `app_main` with `idf.py set-target esp32s2`; `esp_flash.sh --chip
esp32s2` uses it as the harness.

## Procedure for the board session

```sh
. ~/esp/esp-idf/export.sh
make compiler/pascal26

# per board, one line each:
tools/esp_flash.sh --chip esp32s3 test/test_esp_hw_validation.pas
tools/esp_flash.sh --chip esp32s2 test/test_esp_hw_validation.pas
tools/esp_flash.sh --chip esp32c3 test/test_esp_hw_validation.pas
```

Expected: the seven lines below, then `esp_flash: OK — board output matches the
x86-64 oracle`, and an LED on GPIO2 that changed state a few times.

```text
pxx esp hw validation
pow3^20 3486784401
int64min+1 -9223372036854775807
divmod -9223344366821 -675344
vec 7000011 4199 120
string ABCDEFGH 8
ok
```

Things that are expected to bite, so they do not read as failures:

- **Download mode.** If esptool cannot open the chip, hold BOOT and tap RESET,
  then re-run. The script says so on failure.
- **Port permissions.** `/dev/ttyUSB0` needs the `dialout` group (log out and
  back in after adding yourself).
- **Which LED.** GPIO2 is the devkit LED on most S3/C3 boards; several S2 boards
  use GPIO15 or none. A missing LED changes nothing about the diff.
- **`--no-signals`.** Programs that pull the signal runtime must pass
  `ESP_PXXFLAGS="--no-signals"`; without it app_main panics on an `ecall` in its
  prologue. The validation program does not need it.

## The peripheral half is unblocked too (2026-08-02, later)

[[bug-esp-timer-callback-never-dispatched]] is FIXED — it was a 64-bit argument
to a C function being passed with only its low word, so `esp_timer`'s period
arrived with a stale pointer in its high half. Both chips now run the periodic
callback correctly, xtensa included. So the board session gets a second step:

```sh
ESP_PXXFLAGS="--no-signals -Fu$PWD/lib/rtl -Fu$PWD/lib/rtl/platform/esp" \
  tools/esp_flash.sh --chip esp32s3 --no-verify --seconds 15 \
  examples/esp32/timer-c3/main/main.pas
```

Expected:

```text
PXX timer: started
PXX timer: tick=1 ... tick=5
PXX timer: done ticks=5 status=0
```

(`--no-verify` because the demo has no meaningful x86-64 run: it is all SDK
calls.) That satisfies the acceptance's "a basic peripheral/ISR fires" — the
callback is dispatched by the SDK's timer interrupt, which is the real thing on
silicon and only emulated in qemu. `make test-esp-idf` guards the qemu side.

Still worth watching on hardware: qemu's systimer is not the S2/S3 silicon's, so
a timer that works in emulation and not on the board would be new information.
