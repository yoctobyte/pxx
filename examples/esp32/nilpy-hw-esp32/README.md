# NilPy on the classic ESP32: a Python program that drives a pin and takes a timer callback

`examples/esp32/nilpy-hw-c3` and `nilpy-hw-s3` on the third chip — the Xtensa
LX6. The program, its expected output and the build script are **symlinks** to
the C3 project, so all three chips compile the same source by construction and
cannot drift apart:

```text
build.sh           -> ../nilpy-c3/build.sh
main/main.npy      -> ../../nilpy-hw-c3/main/main.npy
main/main.expected -> ../../nilpy-hw-c3/main/main.expected
```

There is no interpreter on the chip. `main.npy` is compiled by pxx's NilPy
frontend straight to a relocatable object for the LX6 and linked by the normal
IDF build; the machine code *is* the program.

```sh
. ~/esp/esp-idf/export.sh
cd examples/esp32/nilpy-hw-esp32
./build.sh                  # or ./build.sh qemu-assert
```

On real silicon, from the repo root:

```sh
tools/esp_flash.sh --project examples/esp32/nilpy-hw-esp32 --port /dev/ttyUSB0
```

Expected output, the same eight lines the C3 and S3 print:

```text
gpio 0
timer 1
tick 1 led 1
tick 2 led 0
tick 3 led 1
tick 4 led 0
tick 5 led 1
done True
```

Nothing in that oracle is chip-specific, which is why one `main.expected` serves
all three.

## IT DOES NOT RUN ON LX6 SILICON YET, and this folder is the reproducer

**Status on the classic ESP32, measured 2026-09-28 with compiler `b2b325036c3b`:
it builds and flashes, and then reboots forever. The failure is LX6-only, and
that is measured rather than inferred:** on the same day, pin v449
(`0ded1e5d04c8`), this same program matched `main.expected` in full — all eight
lines, `timer 1` among them, which is the `esp_timer` callback landing in
compiled code — on **real ESP32-S3 silicon** and on **real ESP32-C3 silicon**,
one boot each, no watchdog. (Those two runs were taken by the seat that owns
those boards; this seat owns only the LX6.) This project is kept precisely because it is the only thing that
reproduces it — **it is not a working example.** The per-chip rows in
`docs/` are maintained by the docs seat; this result was handed over as data so
the tables state the chip and the verdict rather than implying either.

What the board does. A 10 s capture showed only the ROM banner, which looks
exactly like a silent program — the trap `tools/esp_flash.sh` warns about. A 30 s
capture turned that into a diagnosis:

```text
rst:0x8 (TG1WDT_SYS_RESET),boot:0x13 (SPI_FAST_FLASH_BOOT)
...
load:0x40080400,len:3920
entry 0x40080644
        ... and again, three ROM reset cycles inside the window ...
W (74) boot.esp32: WDT rst info: PRO CPU PC=0x4008b13c
W (79) boot.esp32: WDT rst info: APP CPU PC=0x4008b13c
```

So: a Timer Group 1 watchdog reset, in a loop, with **both CPUs stopped at the
same PC**, and the program never reaching its first line (`gpio 0` never
appears).

`0x4008b13c` resolves against `build/pxx_nilpy_hw_esp32.map` to inside
**`_xt_context_save`** (which starts at `0x4008b09c`) — the Xtensa
exception/interrupt context-save path. It is therefore faulting while saving
context, repeatedly, on the **windowed** register-window path. That is the same
area as the windowed-frame bug this tree already fixed in `XtensaExcFrameAddrW`
(`compiler/ir_codegen_xtensa.inc`), which is the first place to look.

### Ruled out, with the measurement

- **Partition overflow.** Both NilPy projects share this `partitions.csv` with
  `factory = 0x3C0000` (~3.9 MB). This image is 1,286,160 bytes and the simple
  `nilpy-esp32` is 1,162,880. Neither is close to the limit, and IDF's own
  `check_sizes.py` passed. This was the most attractive hypothesis and it is
  wrong.
- **A short capture.** 30 s shows three full reset cycles; it is a loop, not
  slow output.
- **NilPy on the LX6, the board, the toolchain and the flash path.** The
  isolating control ran on the SAME board in the same session with the same
  compiler: `examples/esp32/nilpy-esp32` — the simple NilPy program, 1,162,880
  bytes — answered `esp_flash: OK — board output matches
  nilpy-esp32/main/main.expected (4 lines) [rst: 1]`, one boot, rc=0. So a
  static Python program built by pxx does run on this chip; it is this project
  that does not.

### What is NOT established

**The extra components are exonerated, by a discriminator run the same day.**
`examples/esp32/gpio-edge-esp32` requires only `esp_timer esp_driver_gpio lwip
esp_netif` — none of `esp_driver_spi/i2c/rmt` or `pxx_tls` — and it loops
identically on this chip, PRO CPU at `0x4008ae38`, which resolves in *its* map to
inside `_xt_context_save` just as `0x4008b13c` does in this one. Two images, two
addresses, the same function.

So the four extra components are out, and what the pair narrows to is: a **NilPy**
program taking a callback from C into compiled code while using `espgpio`. Plain
NilPy passes on this chip (`nilpy-esp32`, 4-line oracle) and a callback into
**Pascal** passes on this chip (`timer-esp32`, 7-line oracle), so neither NilPy
nor callbacks alone explain it.

Still NOT separated: whether the trigger is `espgpio` specifically or any
C-to-NilPy callback. The next cheap experiment is a NilPy program taking an
`esp_timer` callback with no GPIO at all. Nobody has run it.

Note also that `timer-esp32` — a Pascal program taking an `esp_timer` callback on
this same chip — passes on this board against a byte-compared oracle. So an
esp_timer callback into Pascal on the LX6 is not broken in general.

## Why the shared build script needed no change

`examples/esp32/nilpy-c3/build.sh` already derives the chip from the directory
suffix and already had an `*-esp32` arm, including the two things this chip
needs: `--target=esp32` (the chip name, not `--target=xtensa`, because the
generic spelling answers the S3's memory map) and `--xtensa-long-calls`. The
latter is not optional here and not an LX6 defect — the NilPy runtime is over a
megabyte of code, and without the flag the compiler refuses with "the forward
call to `PyUtf8CpAt` at code offset 501172 cannot reach its body at 1144424".
`--target=esp32s3` refuses identically for the identical source.

## What a run witnesses, and what it does not

The timer callback fires, the loop sees it, and the printed lines match what
CPython prints for the same program with the two modules stubbed. The **LED is
not witnessed**: `gpio_write` executes and returns 0, but nothing here reads the
pin back. That half is for an instrumented board, on any of the three chips.

## Scope

The owner's settled ESP scope is the **S3 and C3**. The classic ESP32 is
**proven where run, not promised**: this example exists because it was run, and
`docs/library/esp.md` states the chip each result was witnessed on.
