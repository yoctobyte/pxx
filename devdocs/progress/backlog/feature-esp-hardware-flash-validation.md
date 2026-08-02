---
prio: 45  # auto
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

## What this ticket can NOT close yet

The acceptance asks for "a basic peripheral/ISR fires on hardware". The timer
callback surface is broken in QEMU on both chips right now
([[bug-esp-timer-callback-never-dispatched]] — filed with a two-file repro), so
that half is blocked. GPIO output IS exercised by the validation program, and
`examples/esp32/timer-s3` is ready as the xtensa retest the moment the callback
bug is fixed. **Worth trying on the board anyway**: if the timer demo works on
real silicon while failing under qemu, that is a large clue for that bug.
