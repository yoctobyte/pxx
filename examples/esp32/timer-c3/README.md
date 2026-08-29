# PXX → ESP-IDF esptimer demo (ESP32-C3)

Slice 1 of the ESP peripheral callback API
(`feature-esp-peripheral-callback-api`): a periodic timer callback through the
`esptimer` unit's event surface — the app assigns `t.OnElapsed := @OnTick` and
calls `TimerStartPeriodicMs(t, 100)`; no `esp_timer_create` args,
`esp_intr_alloc`, or interrupt plumbing appear in app code.

`esp_timer` dispatches callbacks from a high-priority FreeRTOS task (not a
true ISR), so the handler has no ISR-safety restrictions. A hardware
timer-group true-ISR variant is a possible follow-up slice.

Known wart: the callback is marked `iram;` only because plain `@proc` fixups
aren't wired in the relocatable-object writer yet
(`bug-esp-emit-obj-proc-fixup-non-iram`); drop it when that lands.

## Build

```bash
. ~/esp/esp-idf/export.sh     # idf.py + toolchains on PATH
./build.sh                    # main.pas -> main.o -> libpxx_app.a -> idf.py build
./build.sh qemu               # boot under Espressif QEMU (interactive)
./build.sh qemu-assert        # boot + ASSERT the expected sequence, non-interactive
```

## Status: RUNS. Verified under QEMU 2026-08-30.

This example was written 2026-07-11 and went unexecuted for seven weeks because
the ticket recorded, twice, that the box had no runner. That was wrong. Both
Espressif QEMU forks are installed here; IDF puts them **off PATH** under
`~/.espressif/tools/`, where they reach PATH only once `export.sh` is sourced,
so a bare `command -v qemu-system-riscv32` returns nothing and reads as "no
emulator on this machine". Probe for a tool where its installer puts it, not by
asking whether the current shell exposes it.

Actual serial output:

```
I (414) main_task: Calling app_main()
PXX timer: started
PXX timer: tick=1
PXX timer: tick=2
PXX timer: tick=3
PXX timer: tick=4
PXX timer: tick=5
PXX timer: done ticks=5 status=0
```

`status` is a bitmask the app builds itself -- 1 = start failed, 2 = fewer than
five ticks arrived, 4 = stop failed -- so `status=0` cannot be printed by a
timer that never fired; a dead callback prints `status=2`.

**What a green `qemu-assert` witnesses:** a real `esp_timer` callback firing five
times on the emulated C3, dispatched by FreeRTOS through the `esptimer` event
surface, with `TimerStop` returning success.
**What it does not:** silicon. Timing, the physical peripheral and anything
analog are not exercised, and none of it says anything about xtensa (S2/S3) --
that is `timer-s3` and a different QEMU binary.

`bug-esp-idf-heap-linux-mmap-ecall`, which this README previously called a live
blocker, landed on Track A; so did `bug-esp-emit-obj-proc-fixup-non-iram`, and
the interim `iram;` on the callback is gone -- `OnTick` is a plain routine.

### Why `qemu-assert` and not `qemu`

`idf.py qemu monitor` is built for a human at a console and cannot assert.
Piping it does not work either: the app parks forever by design, so any
`| tail` buffers until the timeout kills the pipeline and you capture nothing.
`qemu-assert` drives QEMU directly with the serial line to a file, lets the
timeout fire (rc 124 is expected -- the app is meant to park), and compares
what was captured. It exits 77 with an explanation if the QEMU is absent.

Two bugs found writing it, both of which presented as an EMPTY capture rather
than an error: a missing flash image (`set-target` wipes `build/`), and an
all-zero efuse block -- which reports chip revision v0.0 against an image
requiring >= v0.3, so the bootloader rejects it and reboots forever, filling the
log with boot attempts and no app output. The efuse defaults now come from IDF's
own `QEMU_TARGETS` table rather than a pasted copy.
