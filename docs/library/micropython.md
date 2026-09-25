---
title: MicroPython code on pxx
order: 59
---

# MicroPython code on pxx

Most sensor and display drivers for the ESP32 are written for MicroPython. pxx
compiles Nil Python ahead of time, with no interpreter on the chip, and it
provides MicroPython's module names on the ESP32. The aim is that a published
driver compiles **unchanged**: you copy the driver's `.py` file next to your
program and import it. This page lists what is provided today, how to fetch and
test real drivers, and how far that works so far.

To build and flash a Nil Python program for the ESP32, start with
[Getting started on the ESP32](../getting-started/esp32.md). The lower-level
units underneath (`espgpio`, `espi2c`, `espspi` and the others) are described
in [ESP32 peripherals](./esp.md).

## The approach in one paragraph

**The language is CPython's; the names and platform assumptions are
MicroPython's.** Syntax and semantics follow CPython, so a program that is valid
Python means what it means in CPython. On the ESP32, the modules a driver
imports carry MicroPython's names, argument orders and error behaviour:
`machine.I2C(0, scl=Pin(9), sda=Pin(8))`, `time.sleep_ms()`, an `OSError` with
errno 19 (`ENODEV`) when no device answers. Where the two languages give the
same name different meanings, a CPython name keeps CPython's meaning and a
MicroPython-only name gets MicroPython's (see `utime` below).

**Interrupts are the one deliberate design difference.** MicroPython runs a
`Pin.irq()` handler inside, or close to, the interrupt. pxx never runs your code
in an interrupt: the interrupt records an event, and your handler runs later
from ordinary program flow, where it can print and allocate freely. There is no
`Pin.irq()`. Use the `interrupts` module instead, as shown below.

## What is provided

| Module | What is there |
| --- | --- |
| `machine` | `Pin` (`IN`, `OUT`, `OPEN_DRAIN`, `PULL_UP`, `PULL_DOWN`; `value()`, `on()`, `off()`, calling the pin), `I2C` and `SoftI2C` (`scan`, `writeto`, `writevto`, `readfrom`, `readfrom_into`, `writeto_mem`, `readfrom_mem`, `readfrom_mem_into`), `SPI` (`write`, `read`, `readinto`, `write_readinto`, `deinit`), `RTC` (`datetime()`, `datetime(t)`, `init(t)`) |
| `micropython` | `const()`, imported as `from micropython import const` |
| `framebuf` | `FrameBuffer` in all seven formats (`MONO_VLSB`, `MONO_HLSB`, `MONO_HMSB`, `RGB565`, `GS2_HMSB`, `GS4_HMSB`, `GS8`): `fill`, `pixel`, `hline`, `vline`, `line`, `rect`, `fill_rect`, `scroll`, `blit` (with a transparent key and a palette) and `text` |
| `time` | CPython's `time`, plus MicroPython's `sleep_ms`, `sleep_us`, `ticks_ms`, `ticks_us`, `ticks_cpu`, `ticks_diff` and `ticks_add` |
| `utime` | MicroPython's `utime`, a module of its own: `localtime`, `gmtime`, `mktime` and `time` in MicroPython's forms, plus the sleep and tick functions (see below) |
| `ustruct`, `uos`, … | MicroPython's other old `u`-prefixed names, each an alias of the plain module |
| `network`, `socket`, `open()`, `os` | Wi-Fi, TCP sockets and files, described under **Wi-Fi and sockets** and **Files** in [ESP32 peripherals](./esp.md) |

A project that uses `machine` needs `esp_driver_gpio`, `esp_driver_i2c` and
`esp_driver_spi` in its ESP-IDF `REQUIRES`.

### `machine`: the bus and the error a driver sees

```python
from machine import Pin, I2C
from micropython import const
import time

_ADDR = const(0x3C)
_CONTRAST = const(0x81)

i2c = I2C(0, scl=Pin(9), sda=Pin(8), freq=400000)
print("found:", i2c.scan())
try:
    i2c.writeto(_ADDR, bytes((0x80, _CONTRAST, 0x80, 0x7F)))
    print("display answered")
except OSError as e:
    print("no display:", e)        # [Errno 19] ENODEV, as on MicroPython

led = Pin(2, Pin.OUT)
for i in range(3):
    led.on()
    time.sleep_ms(100)
    led.off()
    time.sleep_ms(100)
```

With no device on the bus, a write fails with `OSError` errno 19 and a bus
timeout with errno 110, just as on MicroPython's ESP32 port, so a driver's
initialisation fails instead of hanging. That errno mapping comes from the
library source and matches MicroPython's ESP32 port. It has not yet been
checked on a board.

Where `machine` differs from MicroPython:

- A program has **one I2C bus and one SPI bus.** A second `I2C(...)` reopens the
  same bus on the new pins.
- `SoftI2C` uses the hardware controller under MicroPython's name. The bytes on
  the wire are the same. The ESP32 can route the hardware controller to any
  pin, so a bit-banged bus is not needed.
- SPI accepts `bits=8` and `firstbit=SPI.MSB` only, which are the values
  published drivers use. The chip-select pin is your program's `Pin`, as in
  MicroPython.
- `Pin` has no `irq()`. See **Interrupts** below.

### `framebuf`

```python
import framebuf

buf = bytearray(128 * 64 // 8)
fb = framebuf.FrameBuffer(buf, 128, 64, framebuf.MONO_VLSB)
fb.fill(0)
fb.text("pxx", 0, 0, 1)
fb.rect(0, 10, 128, 20, 1)
fb.line(0, 63, 127, 32, 1)
print(fb.pixel(0, 10), len(buf))
```

A display driver sends `buf` to the panel byte for byte, so the pixel packing
must be exact. The test `test/lib_mimic_framebuf.npy` draws the same scenes in
every format, including scrolling, blitting, clipping and text. Its output
equals MicroPython 1.26.1's on all 38 lines.

`text()` uses MicroPython's own 8×8 font, copied from MicroPython under its MIT
licence. The copyright notice is kept in the font file, and
`lib/rtl/THIRD-PARTY.md` records where it came from. `ellipse()` and `poly()`
are not provided.

### `machine.RTC` and `utime`

```python
import machine

rtc = machine.RTC()
rtc.datetime((2026, 9, 25, 4, 12, 0, 0, 0))
year, month, day, weekday, hours, minutes, seconds, micros = rtc.datetime()
print(year, month, day, hours, minutes)
```

`RTC.datetime()` uses MicroPython's 8-tuple (the weekday is 0 for Monday, and
the last item is microseconds). The time is UTC, because there are no time
zones. The clock starts from 1970-01-01 at each boot. To keep the time across
a reset, use an external clock chip such as a DS3231.

```python
import utime

t = utime.localtime(86400 * 365)
print(t)
print(utime.mktime(t))
print(utime.mktime((2026, 9, 25, 12, 0, 0, 0, 0)))
```

This prints `(1971, 1, 1, 0, 0, 0, 4, 1)`, `31536000` and `1790337600`.

`utime` uses MicroPython's forms, not CPython's:

- `localtime()` and `gmtime()` return an **8-tuple** (year, month, day, hour,
  minute, second, weekday, day of the year), as MicroPython does. CPython
  returns a 9-field `struct_time`. There are no time zones, so the two
  functions are the same.
- `mktime()` accepts 8 or 9 items, ignores the weekday and day of the year,
  and returns an `int`.
- `time()` returns whole seconds as an `int`.

`time` itself keeps CPython's forms, because a CPython program can import
`time` and none can import `utime`. `import utime as time`, a common line in
drivers, gets `utime`.

**The epoch is 1970-01-01, which differs from MicroPython on the ESP32.**
MicroPython's ESP32 port counts seconds from 2000-01-01, as its v1.26.1 source
shows. pxx counts from 1970 so that `utime.time()` and `time.time()` agree. You
only notice the difference if you store a raw seconds count and read it back
on a board running MicroPython. Code that converts with `localtime` and
`mktime`, as drivers do, gives the same results.

### Interrupts

```python
import interrupts
import 'espgpio.pas' as gpio


def on_edge(ev):
    print("edge on pin", ev.id, "at", ev.ms, "ms")


gpio.gpio_inout(4)
interrupts.on_event(interrupts.INT_SRC_GPIO, on_edge)
gpio.on_change(4)
```

The handler runs from ordinary program flow, never inside the interrupt. The
full interface, including the queue, its counters and what happens when the
queue is full, is under **`interrupts`** in [ESP32 peripherals](./esp.md).

## Trying real drivers

A fetch recipe downloads a set of widely used drivers, each at a pinned
upstream commit. The drivers are downloaded, not included in the pxx source
tree:

```sh
tools/install_lib_candidates.sh micropython-drivers
```

It writes `library_candidates/micropython-drivers/PROVENANCE.md`, which lists
each driver's file, repository and commit. The set has sixteen drivers:

- from micropython-lib: ssd1306, sdcard, dht, ds18x20 (with its onewire
  module) and neopixel;
- by Robert Hammelrath: bme280, ads1x15 and sh1106;
- the MPU6050 from micropython-IMU, and Peter Hinch's DS3231;
- by Mike Causer: max7219 and tm1637;
- st7789 by Russ Hughes, ina219 by Chris Borrill (with micropython-lib's
  `logging`, which its instructions say to copy onto the board), hcsr04 by
  rsc1975, and a bh1750 driver by catdog2.

All are MIT-licensed except hcsr04 and bh1750, which are Apache-2.0.

The recipe skips a download that is already there. If the set has grown since
you last fetched it, fetch again with `FORCE=1` in front of the command.

To measure how many of them compile:

```sh
tools/mpy_driver_census.sh
```

For each driver it compiles a small MicroPython-style main program
(`test/mpy_drivers/m_<driver>.npy`) together with the unchanged driver, for the
ESP32-S3. It then prints a table with the compiler and source revision used.
"Compiles" means an object file was produced; nothing runs on a board. A driver
that has not been downloaded is shown as "not installed", not as an error.

**Each row shows only the first error.** A compile stops at its first error,
so a row cannot show whether more problems follow. When that first problem is
fixed, the driver may compile or it may stop at the next one.

The table on 2026-09-25, with **pin v436** and the source tree at revision
`c253a21ddc` (first error only):

| driver | compiles | first error |
| --- | --- | --- |
| ssd1306, bme280, ads1x15, mpu6050, ds3231, max7219, sdcard, dht, ds18x20, neopixel, sh1106, hcsr04, tm1637, bh1750 | yes | |
| st7789 | no | the `@micropython.viper` decorator, and the `ptr8`/`ptr16` views it uses, are not supported |
| ina219 | no | `logging` sets `self.stream` from a conditional expression whose type the compiler cannot work out yet |

"Compiles" is not "works": the timing-critical functions ds18x20, neopixel,
hcsr04 and dht rely on (`_onewire`, `machine.bitstream`,
`machine.time_pulse_us` and `machine.dht_readinto`) are new and have not yet
been checked on a board.

Every one of these is being worked on, and this table is out of date as soon as
one is fixed. To see the current state, run `tools/mpy_driver_census.sh`.
