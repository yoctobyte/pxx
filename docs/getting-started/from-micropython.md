---
title: Coming from MicroPython
order: 32
---

# Coming from MicroPython

If you already write MicroPython for the ESP32, most of what you know carries
over. PXX compiles the same kind of program, with the same module names, but
it compiles it **ahead of time** into machine code, and that one difference
explains most of what changes. This page lists what stays the same, what is
different, and then moves a real MicroPython script and driver onto an
ESP32-C3.

Every code block on this page was compiled for the ESP32-C3 with pin v445
(compiler sha256 `caf21ac399f1`) on 2026-09-27. For building and flashing in
general, start with [Getting started on the ESP32](./esp32.md).

## What stays the same

- **The language.** Syntax and semantics follow CPython, which MicroPython
  also follows closely: functions, classes, lists, dicts, f-strings,
  exceptions, `try`/`except`.
- **The module names a driver imports.** `machine` (`Pin`, `I2C`, `SoftI2C`,
  `SPI`, `RTC`), `time` with `sleep_ms`, `ticks_ms` and `ticks_diff`, `utime`,
  `micropython.const`, `framebuf`, `network`, `socket`, `urequests`, `ssl`, and
  the old `u`-prefixed aliases. The full list is in
  [MicroPython code on PXX](../library/micropython.md).
- **Published drivers compile unchanged.** 15 of 16 widely used drivers
  compiled without edits in the last census (pin v445, 2026-09-27); you copy the driver's `.py` file
  next to your program, as you would copy it to the board.

```python
from micropython import const
import time

N = const(3)
t0 = time.ticks_ms()
time.sleep_ms(10)
print(N, time.ticks_diff(time.ticks_ms(), t0) >= 10)
```

## What is different

### It is compiled, not interpreted

Your program, the drivers it imports and the runtime become one ESP-IDF
firmware image. There is no Python interpreter on the chip. So:

- **There is no REPL on the board**, and no `mpremote`, `ampy` or Thonny file
  copy. To change the program you rebuild and flash the image; the
  [ESP32 IDE](./esp-ide.md) does both with one button.
- **Imports are resolved when you build.** A missing module or driver is a
  build error, not an `ImportError` on the board.
- **Some mistakes are found at build time.** Calling a method no class has is
  a compile error, not an `AttributeError` at run time. Classes are fixed when
  the program is built: you cannot add or replace a method at run time.
- **`exec` and `eval` run only a small subset of Python**, through a built-in
  tree-walker, and only with an explicit namespace. The subset has no
  `import`, no `class` and no nested `exec`. They are for evaluating
  expressions and simple statements, not for loading new code onto the board.

```python
d = {"x": 2}
exec("y = x * 21", d, d)
print(d["y"], eval("x + 1", d, d))
```

### Interrupts go through an event queue

There is no `Pin.irq()`; a program that calls it does not build (`Pin has no
method irq`). PXX never runs your Python code inside an interrupt. The
interrupt records an event, and your handler runs later, from ordinary program
flow, at `time.sleep`, `time.sleep_ms` or `interrupts.poll()`. In return the
handler may allocate, print and take its time, which a MicroPython ISR may not:

```python
import interrupts
import 'espgpio.pas' as gpio


def on_edge(ev):
    print("edge on pin", ev.id, "at", ev.ms, "ms")


gpio.gpio_inout(4)
interrupts.on_event(interrupts.INT_SRC_GPIO, on_edge)
gpio.on_falling(4)
```

How the queue behaves when it is full, and why a program with an armed pin
keeps running after its last line, is in
[Getting started on the ESP32](./esp32.md#5-talking-to-the-hardware).

### No `@micropython.native` or `@micropython.viper`

Everything is already compiled to machine code, so these decorators have
nothing to add, and PXX refuses them (`unsupported decorator`). Remove them.
A driver that relies on viper's `ptr8` and `ptr16` views, such as st7789,
does not build yet.

### Memory: no garbage collector

MicroPython frees memory with a garbage collector that runs from time to time.
PXX has none: an object is freed when the last reference to it goes away. That
means no collection pauses, and a heap that shows exactly what the program
still holds. It also changes four habits:

- **`gc` is there, but there is nothing for it to collect.** From commit
  `c64b304036` (library code, so the v445 pin compiles it from a tree that has
  it), `import gc` works: `gc.collect()` returns 0, because reference counting
  has already freed everything it could. `gc.mem_free()` and `gc.mem_alloc()`
  report the heap: on the ESP32, ESP-IDF's byte-addressable heap; on a PC,
  PXX's own heap, where `mem_free()` can be 0 in a small program.
  `enable()`, `disable()` and `threshold()` change nothing. With an older tree,
  `import gc` does not build; use `espsys` for the free heap instead:

  ```python
  import 'espsys.pas' as sys
  print(sys.free_heap())
  ```

- **A reference cycle is never freed.** Two objects that point at each other
  keep each other alive after your program has let go of both. A garbage
  collector would find them; reference counting cannot. Measured: this
  function keeps two objects per call unless the last line breaks the cycle,
  and then it keeps none:

  ```python
  class Node:
      def __init__(self):
          self.other = None


  def pair():
      a = Node()
      b = Node()
      a.other = b
      b.other = a
      b.other = None      # break the cycle, or a and b are never freed
  ```

- **Dropping a name does not always free the object at once.** `del name` on
  a local keeps the object until the function returns, up to v448; the
  compiler after v448 (`c4f5dcf929`) frees it at once. On v445,
  `name = None` does not release a list or dict early either. v446 releases
  one built with `[]` and `append` at `name = None`, but keeps a list built by
  a comprehension until the function returns; the compiler after v446
  (`cdd6fd3c1f`) releases that one too.
  What always works: the memory comes back when the function returns. So keep
  large temporary data inside a function rather than at module level, where
  it lives until the program ends.

  ```python
  def handle():
      rows = [str(i) for i in range(100)]
      print(len(rows))
      # rows is released when handle() returns


  handle()
  ```

- **Watch the free heap in a long-running program.** After the first pass it
  should not trend down. See the `free` column in
  [the sensor monitor walk](./esp32.md#4-a-python-program), and the measured
  limits in [Known issues](../reference/known-issues.md#memory-leaks).

### Math errors do not stop the program

On the ESP32, integer division by zero gives 0 and a float division by zero
gives `inf` or `nan`, so one bad sensor reading does not stop a device.
MicroPython raises `ZeroDivisionError`. Test the divisor yourself when zero
means something is wrong. The table is in
[Getting started on the ESP32](./esp32.md#6-arithmetic-errors-do-not-stop-the-chip).

## Moving a real script: an SSD1306 display

A typical MicroPython project is a `main.py` and a driver copied onto the
board. Here the driver is micropython-lib's `ssd1306.py`, unchanged, and the
program draws two lines on a 128x64 I2C display five times.

**1. Fetch the driver.** From the repository root:

```sh
tools/install_lib_candidates.sh micropython-drivers
```

The file is then
`library_candidates/micropython-drivers/micropython-lib/micropython/drivers/display/ssd1306/ssd1306.py`.

**2. Make a project.** Copy an example that already uses the I2C driver, inside
`examples/esp32/` (the build script finds the repository from there). The
directory name must end in `-c3`, `-s3` or `-esp32`; that picks the chip. `-L`
copies the files the example shares with others by link, so your edits stay in
your copy:

```sh
cd examples/esp32
cp -rL nilpy-hw-c3 oled-c3
rm -rf oled-c3/build oled-c3/main/main.expected
cp ../../library_candidates/micropython-drivers/micropython-lib/micropython/drivers/display/ssd1306/ssd1306.py oled-c3/main/
```

Rename the project on the `project(...)` line of `oled-c3/CMakeLists.txt` if
you like; it only names the image file.

**3. The program.** `main.py` becomes `oled-c3/main/main.npy`, unchanged. The
pins are the C3's (SCL on GPIO 9, SDA on GPIO 8); use the ones your display is
wired to:

```python
from machine import Pin, I2C
import ssd1306
import time

i2c = I2C(0, scl=Pin(9), sda=Pin(8), freq=400000)
print("i2c devices:", i2c.scan())
oled = ssd1306.SSD1306_I2C(128, 64, i2c)

n = 0
while n < 5:
    oled.fill(0)
    oled.text("hello from pxx", 0, 0)
    oled.text("count " + str(n), 0, 16)
    oled.show()
    n += 1
    time.sleep_ms(500)
```

**4. Build, then flash.**

```sh
. ~/esp/esp-idf/export.sh
oled-c3/build.sh                                         # build only
cd ../.. && tools/esp_flash.sh --project examples/esp32/oled-c3 --port /dev/ttyACM0 --no-verify
```

Measured with pin v445: `build.sh` compiled `main.npy` and the driver
(`ok: main/main.o [code=2365644B ...]`) and ESP-IDF linked a 2,711,264-byte
image. It was not run on a board for this page. With no display attached,
`machine.I2C` answers a write to an address nobody holds with `OSError` errno
19 (`ENODEV`), as MicroPython does (see
[`machine`: the bus and the error a driver sees](../library/micropython.md#machine-the-bus-and-the-error-a-driver-sees)).

**What changed from the MicroPython version:** the file name, and the build
step. Nothing in the program or the driver.

## When a script does not build

The error names the line. The usual causes, in the order you are likely to
meet them:

| error | cause | what to do |
| --- | --- | --- |
| `no member collect came of the qualifier gc` | a tree before `c64b304036` has no `gc` module, or a file named `gc.py`/`gc.npy` next to yours shadows it | update the tree, or rename your file; or use `espsys.free_heap()` for `gc.mem_free()` |
| `Pin has no method irq` | no `Pin.irq()` | use `interrupts.on_event`, above |
| `unsupported decorator` | `@micropython.native` or `viper` | remove the decorator |
| `undefined variable (match)` | `match` statements are not supported | use `if`/`elif` |

The Nil Python limits that apply everywhere, on the ESP32 and on a PC, are
listed on the [Nil Python page](../targets/nil-python.md#known-limits).
