# PXX ESP32-S3 esptimer demo (Xtensa / windowed)

`examples/esp32/timer-c3` compiled for the other ISA. The source is
byte-identical except for the program name: the point is that the event surface
(`TimerInit` / `OnElapsed` / `TimerStartPeriodicMs`) and a callback taken with
`@` are ABI-portable — nothing in `main.pas` knows which chip it is on.

```sh
. ~/esp/esp-idf/export.sh
make compiler/pascal26
cd examples/esp32/timer-s3
PXX=../../../compiler/pascal26 ./build.sh        # or ./build.sh qemu
```

Expected serial output after the IDF banner:

```text
PXX timer: started
PXX timer: tick=1
...
PXX timer: tick=5
PXX timer: done ticks=5 status=0
```

It does — verified under qemu on 2026-08-02, and this is the first time the
xtensa half ever has. It did not until that afternoon: a 64-bit argument to a C
function was passed with only its low word, so `esp_timer_start_periodic`'s
period arrived with a stale pointer in its high half and the alarm was set some
145,000 years out. Both backends were affected; the write-up is
`devdocs/progress/urgent/bug-esp-timer-callback-never-dispatched.md`.

`make test-esp-idf` now guards both chips against a repeat.

## `./build.sh qemu-assert` — non-interactive, added 2026-08-30

`build.sh qemu` hands you an interactive monitor and cannot assert; piping it
does not work either, because the app parks forever by design. `qemu-assert`
boots QEMU directly with the serial line going to a file, lets the timeout fire
(rc 124 is the expected outcome), and diffs the captured `PXX timer:` lines.

**Measured tonight**, pinned compiler `1d69760deabe`, ESP-IDF v6.0.1, Espressif
QEMU 9.2.2 (`esp_develop_9.2.2_20250817`), `-M esp32s3 -m 32M`:

```text
ESP-ROM:esp32s3-20210327          I (86) boot: chip revision: v0.3
I (71) boot: ESP-IDF v6.0.1       I (453) cpu_start: cpu freq: 160000000 Hz
PXX timer: started … tick=1..5 … done ticks=5 status=0
```

3,069 bytes of serial, a real second-stage bootloader, and `status=0` from a
bitmask the app builds itself (1 = start failed, 2 = fewer than 5 ticks, 4 =
stop failed) — a dead timer prints `status=2`, so this cannot be faked by a
program that merely started.

**What it witnesses:** an `esp_timer` callback dispatched by FreeRTOS through
the library's event surface, on **emulated xtensa silicon**, with the windowed
ABI. **What it does not:** real silicon, timing, or anything analog. Flashing
stays blocked on this box — there is no `/dev/ttyUSB*` — so
`feature-esp-hardware-flash-validation` is untouched by any of this.

### The failure mode to expect is an EMPTY LOG, not an error

Ported from `timer-c3`'s `qemu-assert`, which is the version that is green, and
every deviation is a per-chip difference read out of IDF's own `QEMU_TARGETS`
table rather than guessed — `qemu-system-xtensa` not `-riscv32`, `-m 32M` which
the C3 entry does not carry, and the per-target `nvram.esp32s3.efuse` /
`timer.esp32s3.timg` driver names.

Two harness bugs cost three attempts on the C3 and **both present as an empty
capture**: a missing flash image (`set-target` wipes `build/`) and an all-zero
efuse block (reports chip revision v0.0 against an image needing ≥ v0.3, so the
bootloader rejects and reboots forever). On this lane that matters especially —
"no PXX lines" is indistinguishable from the managed-string defects whose
signature is *printing nothing*. **Check the log's size and its boot banner
before concluding anything about codegen.**

### Emulation coverage, so nobody re-derives it in either direction

`qemu-system-xtensa -machine help` lists `esp32` and `esp32s3`; the riscv32
build lists `esp32c3`. **There is no `esp32s2` machine** — already recorded in
`../hello-s2/README.md`, which is why that project is verified by building
headlessly and running on a board.

The toolchain lives at `~/.espressif/tools/**` and reaches `PATH` only after
`. $IDF_PATH/export.sh`, so `command -v qemu-system-xtensa` in a fresh shell
answers "absent" about the *shell*, not the machine. `tools/esp_run.sh` already
globs the install directory for exactly this reason; copy that, not the `command
-v` probe.
