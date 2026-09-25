---
title: Getting started on the ESP32
order: 30
---

# Getting started on the ESP32

PXX compiles Pascal, C and Nil Python straight to machine code for the ESP32
family. There is no interpreter on the chip: a Python program ends up as xtensa
(ESP32-S2/S3) or RISC-V (ESP32-C3) instructions, linked into an ordinary ESP-IDF
application by ESP-IDF's own build.

This page takes you from an empty machine to a program running on a board. The
reference material (the bare-metal profile, code size, floating point) is in
[ESP32 / Microcontrollers](../targets/esp32.md). To detect, build, flash and monitor from
one window, see [The ESP32 IDE](./esp-ide.md).

**What this page was verified on.** Every command below was run on an
ESP32-S3 devkit (native USB, `/dev/ttyACM0`) with ESP-IDF v6.0.1 and the PXX
compiler named at the bottom of the page. See
[What is and is not proven](#what-is-and-is-not-proven) before you plan
around a chip other than the S3.

## 1. Install ESP-IDF

PXX produces the application object; ESP-IDF provides the bootloader, FreeRTOS,
the drivers, and the final link. Install ESP-IDF v6.0.1 by
[Espressif's instructions](https://docs.espressif.com/projects/esp-idf/en/stable/esp32s3/get-started/),
for the chips you have, into `~/esp/esp-idf` (the tools look there by default;
set `ESP_IDF_DIR` otherwise). Then, in every shell you build from:

```sh
. ~/esp/esp-idf/export.sh
idf.py --version          # ESP-IDF v6.0.1
```

Your user needs to be allowed to open the board's serial port. On most Linux
systems that means the `dialout` group.

The scripts below find the PXX compiler through the `PXX` variable. Point it
at the `pxx` you installed:

```sh
export PXX=/path/to/pxx
```

## 2. A Pascal program

`hello-s3` is a complete ESP-IDF project whose `app_main` is a Pascal program,
`examples/esp32/hello-s3/main/main.pas`. From the repository root:

```sh
tools/esp_flash.sh --project examples/esp32/hello-s3 --port /dev/ttyACM0 --no-verify
```

The script builds the project, writes it to the board, and prints what the
board says on its serial port:

```
PXX hello from Pascal S3: i=1
...
PXX hello from Pascal S3: i=5
PXX S3 sum 1..5 = 15
```

`writeln` works here: it goes to the ESP-IDF console. End every line with a
newline; a partial last line stays in the buffer.

A single `.pas` file needs no project of its own. The short form builds it
into the chip's `hello-*` project, runs the same program on your PC as the
reference, and compares the two outputs:

```sh
tools/esp_flash.sh --chip esp32s3 --port /dev/ttyACM0 myprog.pas
```

## 3. A C program

C goes through the same door, and `main()` works:

```c
#include <stdio.h>
int main(void) {
    printf("hello from C on the S3\n");
    return 0;
}
```

```sh
tools/esp_flash.sh --chip esp32s3 --port /dev/ttyACM0 hello.c
```

PXX compiles C with its own C frontend, not with a vendor compiler. The C
test suite PXX is checked against (c-testsuite, 220 programs) passes 219 of 220
on the ESP32-S3 under Espressif's QEMU; the one skipped needs a writable
filesystem the test image does not mount.

## 4. A Python program

Python on the chip is Nil Python: Python syntax compiled to machine code, not
an interpreter. `examples/esp32/monitor-s3/main/main.npy` is a small sensor
monitor, written the way you would write it on a PC:

```python
import time
import interrupts
import 'espadc.pas' as adc
import 'espgpio.pas' as gpio
import 'espsys.pas' as sys

def on_button(ev):
    state["presses"] += 1
    print(f"button pressed ({state['presses']} so far)")

def main():
    interrupts.on_event(interrupts.INT_SRC_ADC, on_frame)
    interrupts.on_event(interrupts.INT_SRC_GPIO, on_button)
    gpio.gpio_input(BUTTON)
    gpio.on_falling(BUTTON)
    adc.start(ADC_CHANNEL, SAMPLE_HZ)
    for tick in range(1, REPORTS + 1):
        time.sleep(1)
        stats = summarize(collect())
        ...
        print(f"#{tick:3d} mean {stats['mean']:4d} range {stats['min']}..{stats['max']}"
              f" trend {trend:7s} frames {state['frames']} free {sys.free_heap()}")
```

Once a second it averages what the ADC sampled in the background, keeps a
short history in a list, counts presses of the BOOT button and prints a report
with the chip's free heap. After the last report `main()` returns, but the
program keeps running: the button is still armed, so every press still prints
a line (see *the hidden loop* in section 5).

```sh
tools/esp_flash.sh --project examples/esp32/monitor-s3 --port /dev/ttyACM0 --no-verify --seconds 15
```

Measured on the S3 with nothing connected to the ADC pin (GPIO 1), so the
readings sit near the top of the 12-bit range:

```
adc start 0
#  1 mean 3861 range 3772..3881 trend flat    frames 16 free 258100
#  2 mean 3860 range 3840..3881 trend flat    frames 32 free 262084
#  3 mean 3859 range 3837..3879 trend flat    frames 48 free 262076
...
# 10 mean 3859 range 3839..3878 trend flat    frames 160 free 262064
done: history [3860, 3859, 3859, 3860, 3859], free 265088, lowest since boot 238484
main() returned; press BOOT, the hidden loop is still serving it
```

**Watch the `free` column.** It is the first thing to look at in a program that
is meant to keep running. After the first report it must not trend down. Here it alternates between two values about
4 KB apart, 257,948 and 262,072 bytes, depending on whether a buffer is in use
at the moment of the reading. Over a 193-report run (about three and a half
minutes, `REPORTS = 240`) every 40-report window showed exactly that range,
with no drift.

Nil Python is younger than the Pascal and C paths, and known to have plenty of
gaps; [Nil Python's known limits](../targets/nil-python.md#known-limits) list what it does not yet
support. A program that sticks to the shapes above (functions, lists, dicts,
f-strings, `time.sleep`, and the ESP units) is on well-tested ground.

## 5. Talking to the hardware

The ESP units live in `lib/rtl/platform/esp`. Each has a Pascal surface and a
Python surface in the same file: `espgpio` (pins and edge interrupts),
`espadc` (continuous ADC sampling), `esptimer`, `espi2c`, `espspi` (SPI), `esppwm`, `espuart`,
`espnvs` (settings that survive a reboot), `espsys` (free heap, uptime) and
`interrupts`, the event pump. Their full interfaces, and how each one was
checked, are in the [ESP peripheral reference](../library/esp.md).

**How interrupts reach your code.** An interrupt handler written in Pascal
runs in interrupt context and may not allocate, so the units' own handlers do
exactly one thing: they queue an event. Your handler, Pascal or Python, is
registered with `interrupts.on_event(source, handler)` and runs later, in the
main task, at a *blocking point*: `time.sleep`, `sysutils.Sleep`, or an explicit
`interrupts.poll()`. It is ordinary code and may allocate, print or take its
time.

Two consequences worth knowing:

- Nothing is delivered while your program computes without sleeping. That is
  by design: events never interrupt your Python code.
- The queue holds a fixed number of events. Events that arrive while it is
  full are **dropped and counted** (`interrupts.dropped()`), never lost
  silently. Sleep in short steps if a source fires faster than your loop
  sleeps.

**The hidden loop.** When your main program ends while a handler is registered
*and* a source is still open (an armed pin, a running ADC), the program does
not exit. The runtime keeps serving events after the end of the program. Close
the source (`gpio.edge_off(pin)`, `adc.stop()`) and it returns. On a PC the
same program exits normally, because nothing there opens a source.

## 6. Arithmetic errors do not stop the chip

A device that is meant to keep running should not halt because one reading
came out zero. On the ESP targets, Pascal and C follow that rule. Measured on
the S3:

| | Pascal | C | Python |
| --- | --- | --- | --- |
| integer divide by zero (`div`, `/`, `//`) | 0 | 0 | 0 |
| integer remainder by zero (`mod`, `%`) | 0 | 0 | 0 |
| `1.0 / 0.0` | `Inf` | `inf` | `inf` |
| `0.0 / 0.0` | `Nan` | `nan` | `nan` |
| `-1.0 / 0.0` | | | `-inf` |

The divisor was a variable holding zero in every row, so nothing was folded
at compile time. Floats carry NaN forward rather than stopping. On a PC the
same Pascal and C programs stop with runtime error 200, as they always have.

**Exceptions you raise yourself still work.** `try`/`except` in Python and
`try`/`except` in Pascal catch as they do on a PC; measured on the S3 with a
`ValueError` raised and caught.

**An exception nobody catches prints its message, then the program stops.**
The line is the same one a PC prints, `Unhandled exception: <class>: <message>`,
for a Pascal `raise` and for a NilPy `raise` alike. After it the main task
parks in a loop that never returns. About five seconds later ESP-IDF's task
watchdog reports that (`E (5317) task_wdt: Task watchdog got triggered ...`);
with IDF's default settings that is a warning, not a restart. Measured on the
S3 board with the development compiler after pin v425 (v425 itself prints
nothing here and just parks):

```text
before raise
Unhandled exception: ValueError: boom from python
E (5435) task_wdt: Task watchdog got triggered. The following tasks/users did not reset the watchdog in time:
```

**A runtime error prints too**, and then the program ends without a watchdog
report: `{$R+}` indexing past an array printed `Runtime error 201 (range check
error)` on the S3.

So a device that goes quiet after an `Unhandled exception:` line has stopped
there on purpose. To keep it running, catch the error in the main loop:
`try`/`except` in Pascal, `try`/`except` in Python.

## 7. Libraries not yet wrapped

How far the four newest units are tested:

- **`espuart`** is checked on the S3 by `examples/esp32/uart-s3`, with nothing
  wired. Text is sent to the UART's own receiver twice: once through its
  internal loopback, and once through a single pin used for both TX and RX,
  which is the path a real wire takes. It passes at 115,200 and 1,000,000
  baud. A read on an idle line returns empty after the timeout you asked for
  (200 ms measured for 200 ms asked). UART0 is refused, because it carries the
  console.

- **`espnvs`** is checked on the S3 by `examples/esp32/nvs-s3` across four
  boots. Values are written, then read back after a software reboot and after a
  power-on reset. An erased key stays erased across a reboot. A key that was
  never set answers the default you pass. A key longer than 15 characters is
  refused. `set_*` is not durable until `commit()`.

- **`esppwm`** is checked on the S3 by `examples/esp32/pwm-s3`, with nothing
  wired. The chip drives a pin and reads the same pin back: it counts rising
  edges for the frequency and samples the level for the duty. All 15 rows
  pass: 1 kHz, 5 kHz and a 50 Hz servo pulse; a change of frequency that keeps
  the duty; a stopped pin that shows no edges; a fifth pin refused.
- **`espi2c`** is checked on the S3 by `examples/esp32/i2c-s3`. The chip's
  second I2C controller acts as the device. The two controllers cannot share
  pins inside the chip, so the full test needs two jumper wires, GPIO17 to
  GPIO15 and GPIO18 to GPIO16. **Without the wires, only the empty-bus rows have
  run on the board** (open, a scan that finds nobody, a refused address,
  close). Reading and writing a real device has not been run yet.

These ESP-IDF drivers have no PXX unit yet. You can still call them from Pascal
with `external` declarations, as the units above do. The estimates are for a
unit with a Pascal and a Python surface and a board check:

| driver | estimate | note |
| --- | --- | --- |
| Wi-Fi from Pascal | a day | Nil Python already has it: MicroPython's `network` and CPython's `socket`, see [Wi-Fi and sockets](../library/esp.md). `examples/esp32/wifi-ap-s3` brings up an access point from Pascal, with the Wi-Fi bring-up in C |

## What is and is not proven

Everything on this page ran on one ESP32-S3 board. The other chips are less
proven than the S3, and this table says exactly how much less:

| chip | how far it is proven |
| --- | --- |
| **ESP32-S3** | **Run on the board.** `hello-s3`, `timer-s3`, `rgb-s3`, `nilpy-s3`, `nilpy-hw-s3`, `gpio-edge-s3`, `adc-s3`, `monitor-s3`, `pwm-s3`, `i2c-s3` (empty bus only, see section 7) and `nilpy-station-s3` (its HTTP self-fetches; see [Wi-Fi and sockets](../library/esp.md)). `wifi-ap-s3` brings its access point up, but no client has connected to it yet. The C conformance suite passes 219 of 220 under the S3's QEMU (`tools/run_c_conformance_esp.sh --chip esp32s3`; one test skipped). |
| **ESP32-C3** | **QEMU only, never on a board.** `hello-c3`, `timer-c3`, `nilpy-c3`, `nilpy-hw-c3`, `isrctx-c3`, `fs-c3`, `gpio-c3`, `net-c3` and `dns-c3` run under Espressif's QEMU. `adc-c3` and `gpio-edge-c3` build, but QEMU has no ADC or GPIO input to drive them, so they are unverified. |
| **ESP32-S2** | **Builds only.** `hello-s2` compiles and links for it; it has not been run anywhere. |
| **ESP32 (the original)** | **QEMU only, and by hand.** A Pascal program (integer division, `Int64`, `Double`, strings, a class) and a Python program match the PC's output under Espressif's QEMU (`qemu-system-xtensa -M esp32`), built with `--target=esp32` into a copy of an IDF project set to the esp32 target. There is no example project for this chip, `tools/esp_flash.sh` and `tools/esp_run_bare.sh` do not accept it, and it has not been run on a board. |

"Runs" means the program's output matched what it is expected to print; for
the examples with a `.expected` file, byte for byte.

## Verified with

One ESP32-S3 devkit on `/dev/ttyACM0`, ESP-IDF v6.0.1, CPU at 160 MHz,
2026-09-24/25.

- **Every command and every example on this page** was run on the board with
  the compiler of pin v424 (binary sha256 `93a336a7ba85`, repository at
  `cf8d0064f`). Fifteen of fifteen passed: `nilpy-s3`, `nilpy-hw-s3`,
  `gpio-edge-s3` and `adc-s3` match their expected output byte for byte;
  `hello-s3`, `timer-s3`, `rgb-s3`, `wifi-ap-s3` (up to "listening"),
  `i2c-s3`, `pwm-s3`, `uart-s3` and `nvs-s3` print their own pass lines; the
  `myprog.pas` and `hello.c` short forms match the PC. `monitor-s3` was run
  with that compiler too, and with the later one below.
- **The same walk with pin v425** (binary sha256 `426b2fbf3f08`, repository at
  `4fbf33f69`), on 2026-09-25: fifteen of fifteen passed again, each judged
  the same way, and both short forms match the PC. `monitor-s3` with
  `REPORTS = 10` reads an ADC mean of 3861 to 3863 and free heap between
  257,976 and 262,088 bytes.
- **The heap figures** were measured with a later compiler (`29956ba5beff`,
  repository at `9c14efd7b`), which carries two leak fixes made during this
  check. `monitor-s3` is flat with both. Three examples, each re-run in a
  loop, lost bytes on every pass with an earlier compiler (`bb17d23beea5`):
  `nilpy-s3` about 44, `nilpy-hw-s3` about 220, `gpio-edge-s3` about 264.
  Pin v424 predates that fix, so expect the same from it; v425 carries it.
  With the later compiler all three are flat. `adc-s3` run in a loop lost about
  17.5 KB per pass with both of those compilers, because an `adc.read()` whose
  result is thrown away was not released: with `bb17d23beea5` its free heap
  fell from 253,688 to 78,252 bytes by pass 10. v425 carries that fix too
  (`c4eb85dc39`): with pin v425, 60 passes keep the free heap at 271,232 bytes
  from pass 0 to pass 60, with the lowest point at 264,440 throughout, the same
  as compiler `790bc11fb9c2` (built from `e94295369`) measured before the pin.
  On v424, assign the result, as `monitor-s3` does.
