---
title: ESP32 peripherals
order: 58
---

# ESP32 peripherals — `espgpio`, `espuart`, `espadc`, `esppwm`, `espi2c`, `espnvs`, `esptimer`, `espsys`, `interrupts`

These units drive the ESP32's hardware from Pascal and from Nil Python. This
page is the reference: what each unit does, its interface as the unit declares
it, and how far it has been tested. To set up ESP-IDF, build and flash a first
program, start with [Getting started on the ESP32](../getting-started/esp32.md).

All of them are **ESP-IDF only**. They resolve when ESP-IDF links your program,
so they do not work in a bare-metal image, and each needs an ESP-IDF component
in your project's `REQUIRES`, listed per unit below. The units live in
`lib/rtl/platform/esp/`, except `interrupts`, which is in `lib/rtl/`.

## One unit, two languages

Every unit has a Pascal surface and a Nil Python surface. The Python names are
lowercase `snake_case` wrappers over the same code, so the two never differ in
behaviour:

```pascal
uses espnvs;
...
NvsSetInt('boots', NvsGetInt('boots', 0) + 1);
NvsCommit;
```

```python
import 'espnvs.pas' as nvs
nvs.set_int("boots", nvs.get_int("boots", 0) + 1)
nvs.commit()
```

In Python, a peripheral unit is imported by file name, as above. `interrupts`
is the exception: it is a registered Python module, imported as
`import interrupts`.

The Python half of `interrupts`, `espadc`'s `read`, `espi2c` and `espuart`
passes lists or events, or would hide Pascal's own `Write`/`Read`, so it is
compiled only into Nil Python programs. A Pascal program that uses these units
does not carry the Python runtime.

Everything on this page compiles with **pin v424** (compiler sha256
`93a336a7ba85…`) from both languages, for both the ESP32-S3 (xtensa) and the
ESP32-C3 (riscv32). `espuart` is newer than v424's commit, so it needs a
checkout at or after `bf67f1a46`; it is library source, so the v424 compiler
builds it.

## How it was verified

The ESP lane (frankh-95) ran every example below on **one ESP32-S3 board**
(ESP-IDF v6.0.1, 160 MHz), with the v424 compiler, and all 15 passed. The
units that open and close a peripheral (timer, PWM, I2C, UART) were also run
through 300 open/use/close cycles each, and none of them leaked memory. The
`monitor-s3` example, which reads the ADC, GPIO and heap together, ran 193
reports over 3.5 minutes with free heap flat. **The ESP32-C3 has
been tested only under QEMU, and the ESP32-S2 has only been built.** QEMU
models no GPIO input and no ADC, so the input half of `espgpio` and all of
`espadc` can only be checked on a board.

| Unit | Example | On the ESP32-S3 board |
| --- | --- | --- |
| `espgpio` + `interrupts` | `gpio-edge-s3` (Python) | output matches `main.expected` |
| `espuart` | `uart-s3` | 13 of 13 checks, with nothing wired |
| `espadc` + `interrupts` | `adc-s3` (Python) | output matches `main.expected` |
| `esppwm` | `pwm-s3` | 15 of 15 checks, with nothing wired |
| `espi2c` | `i2c-s3` | 5 of 5 checks on an empty bus; **no device tested** |
| `espnvs` | `nvs-s3` | 0 failures over four boots |
| `esptimer` | `timer-s3`, `nilpy-hw-s3` | runs as intended |
| `espsys` | `uart-s3` | used for the heap figures in the checks above |

The examples are in `examples/esp32/<name>/`. Each builds with `./build.sh`
and flashes with `tools/esp_flash.sh --project examples/esp32/<name>`.

## `espgpio` — pins

`REQUIRES esp_driver_gpio`

| Pascal | Python | What it does |
| --- | --- | --- |
| `GpioReset(pin)` | | reset a pin to its default state |
| `GpioSetDirection(pin, mode)` | `gpio_output(pin)`, `gpio_input(pin)`, `gpio_inout(pin)` | set a pin to output, input or both (`GPIO_MODE_*`) |
| `GpioSetLevel(pin, level)` | `gpio_write(pin, level)` | drive a pin 0 or 1 |
| `GpioGetLevel(pin)` | `gpio_read(pin)` | read a pin |
| | `gpio_pullup(pin)`, `gpio_pulldown(pin)` | enable the internal pull resistor |
| `GpioArmEdge(pin, kind)` | `on_rising(pin)`, `on_falling(pin)`, `on_change(pin)`, `edge_off(pin)` | turn each edge on the pin into an `interrupts` event (`GPIO_EDGE_*`) |
| `GpioEdgeCount` | `gpio_edges()` | edges the interrupt has counted since boot |

Everything returns ESP-IDF's error code, where 0 means success. Arming an edge
does not change the pin's direction, so make it an input first. A pin set with
`gpio_inout` feeds its own input, so writing it produces a real edge with
nothing wired. That is how the examples test themselves.

`gpio_input` leaves the pull-up on, so a button to ground reads 1 at rest and
gives a falling edge when pressed. On an ADC pin, set the pull resistor *after*
`adc.start`: the ADC driver clears it when it takes the pin.

## `interrupts` — events from hardware, handled outside the interrupt

An interrupt never runs your code. The interrupt only records an event in a
64-entry queue: which source, which pin or channel, and when. Your handler runs
later, from ordinary program flow, so it can print, allocate and call anything.
That holds in Pascal and in Python alike.

```python
import interrupts
import 'espgpio.pas' as gpio

def on_edge(ev):
    print("edge on pin", ev.id)

gpio.gpio_inout(4)
interrupts.on_event(interrupts.INT_SRC_GPIO, on_edge)
gpio.on_change(4)
```

| Pascal | Python | What it does |
| --- | --- | --- |
| `IntOnEvent(source, cb)` | `on_event(source, cb)` | register a handler for one source; `nil` / `None` removes it |
| `IntPoll` | `poll()` | run the handlers for waiting events now |
| `IntNext(ev)` | `events()` | take waiting events without running handlers; Python gets a list of `event` objects with `source`, `id`, `seq` and `ms` |
| `IntPending`, `IntDropped`, `IntDelivered` | `pending()`, `dropped()`, `delivered()` | queue counters |
| `IntPush(source, id)` | `push(source, id)` | add an event yourself |
| `IntLiveSources` | `live_sources()` | how many armed sources can still produce events |

Sources: `INT_SRC_GPIO` (the id is the pin), `INT_SRC_ADC` (the id is the
channel), `INT_SRC_TIMER` and `INT_SRC_USER`.

**When handlers run.** Handlers run whenever the program blocks in the runtime,
for example in a sleep, and whenever it calls `poll()`. Each run handles at
most 16 events, and a handler that blocks does not start a second run inside
itself.

**When the queue is full.** A new event is dropped and counted in `dropped()`.
Every event is accounted for: the events pushed equal the events delivered
plus the events dropped.

**A script can simply end.** If a program has registered a handler and still
has an armed source, reaching the end of the program does not stop it: it keeps
handling events until the last source is disarmed (`edge_off`, `adc.stop`).
Then it ends normally. On a desktop there is no such source, so this never
applies there.

The names follow MicroPython where a name existed, but the design is not
MicroPython's: there is no `machine.Pin` and no `Pin.irq`.

## `espadc` — continuous analog sampling

`REQUIRES esp_adc`

| Pascal | Python | What it does |
| --- | --- | --- |
| `AdcStart(channel, sampleHz)` | `start(channel, sample_hz)` | sample one ADC1 channel continuously |
| `AdcStop` | `stop()` | stop sampling |
| | `read()` | the raw 12-bit samples waiting now, as a list of ints; never waits |
| `AdcFrameCount` | `frames()` | frames the driver has reported since boot |
| `AdcPoolOverflows` | `overflows()` | times the driver's buffer was full and a frame was dropped |
| | `channel_pad(ch)` | the GPIO pin behind a channel on this chip (channel 0 is GPIO1 on the S3, GPIO0 on the C3) |

Each completed frame is an `interrupts` event with source `INT_SRC_ADC`. A
handler fetches the samples with `read()`. **With pin v424, keep the
result**: an `adc.read()` whose list is thrown away is never freed, and in a
loop that costs about 17.5 KB per pass on the S3 board. Assigning the list or
looping over it frees it. This is fixed after v424 (`c4eb85dc39`), so the next
pin releases a discarded result too. Only ADC unit 1 is supported, one
channel at a time, at 12 dB attenuation and 12 bits. There is no Pascal
function that returns samples yet; reading them is Python-only.

## `espuart` — serial ports

`REQUIRES esp_driver_uart`. Needs a checkout at or after `bf67f1a46`.

| Pascal | Python | What it does |
| --- | --- | --- |
| `UartOpen(port, txPin, rxPin, baud)` | `open(port, tx, rx, baud)` | open UART1 (or UART2 on the S3) |
| `UartClose(port)` | `close(port)` | close it |
| `UartWriteStr(port, s)`, `UartWrite(port, buf, n)` | `write(port, s)` | queue bytes to send |
| `UartReadStr(port, maxLen, timeoutMs)`, `UartRead(port, buf, n, timeoutMs)` | `read(port, max_len, timeout_ms)` | wait up to the timeout for bytes, and return what came (possibly fewer, or `''`) |
| `UartAvailable(port)` | `available(port)` | bytes received and not yet read |
| `UartFlush(port, timeoutMs)` | `flush(port, timeout_ms)` | wait until everything written has been sent |
| `UartLoopback(port, enable)` | `loopback(port, 0 or 1)` | connect the port's TX to its own RX inside the chip, for a self-test |

The settings are 8 data bits, no parity, 1 stop bit and no flow control, and
received bytes wait in a 1 KB buffer between reads. **UART0 is refused**: it
carries the console, and taking it over would silence `print` and `WriteLn`.

## `esppwm` — PWM output

`REQUIRES esp_driver_ledc`

| Pascal | Python | What it does |
| --- | --- | --- |
| `PwmStart(pin, freqHz, dutyPerMille)` | `start(pin, freq_hz, duty_per_mille)` | start PWM on a pin |
| `PwmSetDuty(pin, dutyPerMille)` | `duty(pin, duty_per_mille)` | change the duty cycle |
| `PwmSetPulseUs(pin, us)` | `pulse_us(pin, us)` | set the high time directly, as servos are specified |
| `PwmSetFreq(pin, freqHz)` | `freq(pin, freq_hz)` | change the frequency, keeping the duty cycle |
| `PwmStop(pin)` | `stop(pin)` | stop |
| `PwmBits(pin)` | `bits(pin)` | the resolution chosen for this frequency |

**Duty is per mille (0 to 1000), not per cent.** Up to four pins can run at
once, each at its own frequency; a fifth `start` returns
`ESP_ERR_NOT_FOUND`. The resolution is picked from the frequency: 50 Hz gets 14
bits, which is a servo step of about 1.2 µs.

## `espi2c` — I2C bus master

`REQUIRES esp_driver_i2c`

| Pascal | Python | What it does |
| --- | --- | --- |
| `I2cOpen(port, sda, scl, hz)` | `open(sda, scl, hz)`, `open_port(port, sda, scl, hz)` | open the bus; port -1 lets ESP-IDF choose |
| `I2cClose` | `close()` | close it |
| `I2cProbe(addr)` | `probe(addr)` | 0 if a device answers at the 7-bit address |
| | `scan()` | the list of addresses that answer |
| `I2cWrite(addr, data, len)` | `write(addr, [bytes])` | write bytes to a device |
| `I2cRead(addr, data, len)` | `read(addr, n)` | read bytes from a device |
| `I2cWriteRead(addr, wr, wlen, rd, rlen)` | `write_read(addr, [bytes], n)` | write, then read with a repeated start: the usual register read |

There is one bus per program, and devices on it are added on first use. In
Python, bytes go in and out as lists of ints from 0 to 255, and a failed read
returns an empty list.

**Reading and writing a real device has not been tested.** The board checks
covered opening the bus, scanning an empty bus, and reporting a missing
device. The device test needs two jumper wires (GPIO17 to GPIO15 and GPIO18 to
GPIO16) that have not been fitted yet. The clock source is set per chip and
was checked on the S3 only.

## `espnvs` — settings that survive a reboot

`REQUIRES nvs_flash`, and a partition table with an NVS partition (ESP-IDF's
stock tables have one).

| Pascal | Python | What it does |
| --- | --- | --- |
| `NvsSetInt(key, value)`, `NvsSetStr(key, value)` | `set_int(key, value)`, `set_str(key, value)` | store a value |
| `NvsGetInt(key, fallback)`, `NvsGetStr(key, fallback)` | `get_int(key, fallback)`, `get_str(key, fallback)` | read a value, or the fallback if it is absent |
| `NvsErase(key)` | `erase(key)` | remove a key |
| `NvsCommit` | `commit()` | make the writes durable |
| `NvsLastError` | `last_error()` | the error code of the last call |
| `NvsOpenNamespace(ns)` | | switch namespace (Pascal only) |

**Nothing is durable until `commit`**: a power cut before it loses the writes.
Keys are at most 15 characters. Everything goes into one namespace, `pxx`. If
the partition is full or in a newer format on first use, it is erased and
initialised again, which is ESP-IDF's own recovery and loses what was stored.

## `esptimer` — periodic and one-shot timers

`REQUIRES esp_timer` (every example project has it).

| Pascal | Python | What it does |
| --- | --- | --- |
| `TimerInit(t)`, then set `t.OnElapsed` | | prepare a `TEspTimer` record and its callback |
| `TimerStartPeriodicMs(t, ms)` | `timer_start_periodic_ms(ms)` | fire every `ms` milliseconds |
| `TimerStartOnceMs(t, ms)` | `timer_start_once_ms(ms)` | fire once after `ms` milliseconds |
| `TimerStop(t)` | `timer_stop()` | stop |
| `TimerDone(t)` | `timer_done()` | stop and release the timer |
| | `timer_ticks()` | how many times the timer has fired |
| | `sleep_ms(ms)` | yield to FreeRTOS for `ms` milliseconds |

A Pascal callback runs in ESP-IDF's timer task, not in an interrupt, so it may
print or allocate, but keep it short: every timer shares that task. Python has
no callback here. It starts the unit's single timer and reads
`timer_ticks()`. **A Python loop that polls must call `sleep_ms`**, or the
chip's watchdog resets it.

## `espsys` — heap and uptime

No extra component.

| Pascal | Python | What it does |
| --- | --- | --- |
| `EspFreeHeap` | `free_heap()` | free heap now |
| `EspMinFreeHeap` | `min_free_heap()` | lowest free heap since boot |
| `EspLargestFreeBlock` | `largest_free_block()` | largest single allocation that would succeed now; it falls first when the heap fragments |
| `EspUptimeMs` | `uptime_ms()` | milliseconds since boot |

A program meant to run for a long time should watch `free_heap()`: a leak
produces no wrong output, only a free heap that keeps falling.

## Math errors do not stop the chip

An embedded device should keep running when a sensor produces a value that
causes a math error, so on the ESP32 family:

- integer `div` and `mod` by zero give 0 (Pascal and C), and `//` and `%` by
  zero give 0 (Nil Python);
- a float division by zero gives Inf or NaN;
- nothing halts the program.

On a desktop target the same integer division stops the program with runtime
error 200. [Known issues](../reference/known-issues.md#by-design-math-errors)
has the full table as measured on v424. If a zero divisor must stop your ESP
program, test the divisor yourself.

## Next

- [Getting started on the ESP32](../getting-started/esp32.md): setting up
  ESP-IDF and building a first program.
- [ESP32](../targets/esp32.md): the two build modes, code size and floating point.
- [Examples showcase](../examples/index.md#esp32): the ESP examples and their outputs.
- [Known issues in beta 0.1](../reference/known-issues.md)
