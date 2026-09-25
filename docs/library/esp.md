---
title: ESP32 peripherals
order: 58
---

# ESP32 peripherals — `espgpio`, `espuart`, `espadc`, `esppwm`, `espi2c`, `espspi`, `espnvs`, `esptimer`, `espsys`, `interrupts`

These units drive the ESP32's hardware from Pascal and from Nil Python. This
page is the reference: what each unit does, its interface as the unit declares
it, and how far it has been tested. To set up ESP-IDF, build and flash a first
program, start with [Getting started on the ESP32](../getting-started/esp32.md).

Wi-Fi and TCP sockets from Nil Python, with MicroPython's `network` and
CPython's `socket`, and files on flash with Python's `open()` and `os`, are
covered near the end of the page, under **Wi-Fi and sockets** and **Files**.

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

The Python half of `interrupts`, `espadc`'s `read`, `espi2c`, `espspi` and
`espuart` passes lists or events, or would hide Pascal's own `Write`/`Read`, so it is
compiled only into Nil Python programs. A Pascal program that uses these units
does not carry the Python runtime.

Everything on this page compiles with **pin v425** (compiler sha256
`426b2fbf3f08…`) from both languages, for both the ESP32-S3 (xtensa) and the
ESP32-C3 (riscv32): one Pascal program and one Nil Python program that use every
unit were compiled for each chip on 2026-09-25, and `espspi`, which landed
after that, was compiled the same way from both languages the same day.

## How it was verified

Every example below was run on **one ESP32-S3 board**
(ESP-IDF v6.0.1, 160 MHz), with the v424 compiler and again with the v425
compiler, and all 15 passed both times. `spi-s3` is newer and has run on
the v425 compiler only. The
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
| `espspi` | `spi-s3` | 18 of 18 checks with nothing wired, on v425; **no device tested** |
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
handler fetches the samples with `read()`. From pin v425 a result that is
thrown away is released too: `adc-s3` looped 60 times on the S3 board keeps its
free heap at 271,232 bytes. **With pin v424, keep the result**: there, an
`adc.read()` whose list is thrown away is never freed, which costs about
17.5 KB per pass. Only ADC unit 1 is supported, one
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

## `espspi` — SPI bus master

`REQUIRES esp_driver_spi`

| Pascal | Python | What it does |
| --- | --- | --- |
| `SpiOpen(host, sck, mosi, miso)` | `open(sck, mosi, miso)`, `open_host(host, sck, mosi, miso)` | open the bus; `open` uses `SPI2_HOST` |
| `SpiClose` | `close()` | close the bus and remove its devices |
| `SpiIsOpen` | | whether the bus is open |
| `SpiAddDevice(cs, hz, mode)` | `device(cs, baudrate, mode)` | add a device by its CS pin, SPI mode 0 to 3 |
| `SpiActualKHz(cs)` | | the clock the driver actually chose, in kHz |
| `SpiTransfer(cs, wr, rd, len)` | `write_readinto(cs, [bytes], buf)` | write and read at the same time |
| `SpiWrite(cs, data, len)` | `write(cs, [bytes])` | write bytes |
| `SpiRead(cs, data, len, fill)` | `read(cs, n, fill)`, `readinto(cs, buf, fill)` | read bytes, clocking out `fill` meanwhile |

There is one bus per program, and several devices can share it, such as a
display and an SD card. Every transfer names its device by its CS pin, the way
`espi2c` names one by its address. A device whose CS line your program drives
itself is added with `cs = -1`. `SPI2_HOST` is 1; the S3 and S2 also have
`SPI3_HOST` (2).

Transfers are polled, so they spin instead of sleeping, which suits short
sensor transactions. DMA is on, so one Pascal transfer can be up to 4,096
bytes. In Python, bytes go in and out as lists of ints from 0 to 255, at most
256 per call, and a failed `read` returns an empty list. Errors are ESP-IDF
codes: `SPI_ERR_INVALID_ARG`, `SPI_ERR_NOT_OPEN`, `SPI_ERR_NOT_FOUND`,
`SPI_ERR_NOT_SUPPORTED`.

The clock source is set per chip, and only the S3, C3 and S2 are in the table.
`SpiOpen` on any other chip returns `SPI_ERR_NOT_SUPPORTED` instead of guessing.

**Talking to a real device has not been tested.** The `spi-s3` checks ran on
the S3 board with pin v425 and nothing wired: MISO read `$FF` with its pull-up
and `$00` with its pull-down, a GPIO-matrix loopback echoed the bytes written,
and a 1,024-byte write took 8,255 µs at 1 MHz and 1,071 µs at 8 MHz. Under
QEMU the S3 opens the bus, adds devices and reads the clock back, but no
transfer runs, because QEMU's SPI never completes one. For the C3 the unit
has only been compiled, and nothing has been built for the S2.

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

## Wi-Fi and sockets — `network`, `socket` (Nil Python)

A Nil Python program on the ESP32 brings up Wi-Fi with MicroPython's
`network` module and talks TCP with CPython's `socket` module. Both use the
names a MicroPython or CPython programmer already knows. They are Python
modules only: there is no Pascal surface for Wi-Fi yet.

`import network` works only in an ESP build. `import socket` is the same module
on a desktop and on the ESP32, so a server written against CPython's names runs
on both.

**Your project needs the `pxx_esp` component.** It is the C half of `network`,
in `lib/rtl/platform/esp/idf/pxx_esp`. Copy `CMakeLists.txt` and
`main/CMakeLists.txt` from `examples/esp32/nilpy-station-s3`: the first adds
the component folder with `EXTRA_COMPONENT_DIRS`, and the second lists
`pxx_esp` in `REQUIRES`. Without it, the link fails and names
`pxx_wifi_ap_start`.

### An access point

```python
import network

ap = network.WLAN(network.AP_IF)
ap.config(essid="MY-BOARD", password="choose-a-password")
ap.active(True)
print(ap.ifconfig())   # ('192.168.4.1', '255.255.255.0', '192.168.4.1', '0.0.0.0')
```

Call `config()` before `active(True)`: the settings are applied when the
access point starts, and `config()` on a running access point restarts it.
`ssid=` is accepted as another spelling of `essid=`, as newer MicroPython
versions accept it. `ap.status('stations')` answers how many stations are
connected.

### Joining a network (station)

**Board plus your Wi-Fi.** Put your own network's name and password where the
placeholders are.

```python
import network
import time

sta = network.WLAN(network.STA_IF)
sta.active(True)
for ssid, bssid, channel, rssi, auth, hidden in sta.scan():
    print(ssid, channel, rssi, auth == network.AUTH_OPEN)

sta.config(reconnects=3)             # give up after three retries; -1 (the default) retries forever
sta.connect("<your-ssid>", "<your-password>")
while sta.status() == network.STAT_CONNECTING:
    time.sleep(0.25)

if sta.isconnected():
    ip, mask, gateway, dns = sta.ifconfig()
    print("address", ip, "signal", sta.status("rssi"), "dBm")
elif sta.status() == network.STAT_WRONG_PASSWORD:
    print("wrong password")
elif sta.status() == network.STAT_NO_AP_FOUND:
    print("no such network")
else:
    print("not connected, status", sta.status())
```

This follows MicroPython's ESP32 port:

- `connect()` returns at once. The Wi-Fi driver keeps retrying in the
  background, until `config(reconnects=n)` runs out.
- `status()` is `STAT_IDLE` before `connect()`, `STAT_CONNECTING` while it
  tries and `STAT_GOT_IP` once connected. If a try fails, it keeps the reason
  while the driver retries, so the loop above ends instead of spinning:
  `STAT_NO_AP_FOUND` (201) for a network that is not there,
  `STAT_WRONG_PASSWORD` (202) for a wrong password. The values are
  MicroPython's.
- `scan()` needs an active station. It returns one tuple per network seen:
  `(ssid, bssid, channel, rssi, authmode, hidden)`. `ssid` is `bytes`,
  `bssid` is 6 `bytes`, and `authmode` is one of `AUTH_OPEN`, `AUTH_WEP`,
  `AUTH_WPA_PSK`, `AUTH_WPA2_PSK`, `AUTH_WPA_WPA2_PSK`, `AUTH_WPA2_ENTERPRISE`,
  `AUTH_WPA3_PSK` or `AUTH_WPA2_WPA3_PSK`. `hidden` is always `False`.
- `ifconfig()` is `(ip, netmask, gateway, dns)`. It answers `'0.0.0.0'` for
  the address until the station has one.
- `status('rssi')` is the signal strength of the network you joined, in dBm.
- The access point and the station can be active at the same time.
- `disconnect()` leaves the network, and `active(False)` turns the station off.

### Where it differs from MicroPython

- `status('stations')` answers the **number** of connected stations, where
  MicroPython answers a list of them.
- `connect(bssid=...)` is not supported, and neither is the query form of
  `config()`, such as `config('mac')`.
- Nothing is stored in flash. The network name and password your program
  passes are kept in RAM only. MicroPython's ESP32 port does the same.

### Sockets, timeouts and errors

`socket` covers IPv4 TCP: `socket()`, `bind`, `listen`, `accept`, `connect`,
`recv`, `send`, `sendall`, `close`, `setsockopt(SOL_SOCKET, SO_REUSEADDR, 1)`,
`setblocking`, `settimeout`, `gettimeout`, `getsockname`, `fileno`, and
`with`. A host is a dotted address such as `'192.168.4.1'`, `''` or
`'0.0.0.0'` for any address, or `'localhost'`. It refuses other host names,
because there is no name lookup, and it refuses any socket that is not
`AF_INET`, `SOCK_STREAM`.

`settimeout()` works in CPython's three modes. `None` blocks, `0` never
waits, and a number of seconds makes `connect`, `accept`, `recv` and `send`
give up after that long with `TimeoutError('timed out')`.

Errors are raised the way CPython on Linux raises them: the `OSError`
subclass that the error number selects, with the same text. So a program
catches the same exceptions and prints the same messages on the board as on a
desktop. `socket.error` is `OSError`, as in CPython 3.

```python
import socket

c = socket.socket()
c.settimeout(2.0)                    # None blocks, 0 is non-blocking, t > 0 gives up after t seconds
try:
    c.connect(("192.168.4.2", 80))
    c.sendall(b"GET / HTTP/1.0\r\n\r\n")
    print(c.recv(512))
except ConnectionRefusedError as e:
    print("refused:", str(e))             # refused: [Errno 111] Connection refused
except TimeoutError as e:
    print("gave up:", str(e))             # gave up: timed out
except OSError as e:
    print("other:", str(e))
c.close()
```

`test/esp_board_socket_errors.npy` provokes each case on the board. Each line
it printed is the text before the colon, then the exception's class name
where the test prints one, then `str(e)`:

```text
non-blocking accept: [Errno 11] Resource temporarily unavailable
accept timeout: TimeoutError timed out after 250..1000 ms True
refused connect, timeout None : ConnectionRefusedError [Errno 111] Connection refused
refused connect, timeout 1.0 : ConnectionRefusedError [Errno 111] Connection refused
unreachable host: TimeoutError timed out within 3 s True
recv timeout: TimeoutError timed out
```

The first line is an `accept()` on a non-blocking socket with nobody waiting,
which raises `BlockingIOError`. The unreachable host is an address on the
board's own network that nobody answers: the `connect()` ends at its timeout
instead of hanging.

### The example: `nilpy-station-s3`

`examples/esp32/nilpy-station-s3` is a status page in Python. The board starts
its own Wi-Fi network, `PXX-NILPY` with the password `pascal26`, and serves a
page at `http://192.168.4.1/`. The page shows an ADC reading, the chip's
temperature, uptime, free heap and the number of connected stations, and it
updates once a second. It uses `network`, `socket` and `json`, plus `espadc`
and `espsys`.

The main body sets everything up and then ends. The page keeps being served
from `interrupts`' hidden loop: each ADC frame, about 16 a second, answers the
requests that are waiting. Before its main body ends, the program fetches its
own `/` and `/data` over `127.0.0.1`. It fetches `/data` once more from inside
the hidden loop. So a board run with no phone still checks the HTTP path, and
checks that serving goes on after the main body has ended:

```sh
tools/esp_flash.sh --project examples/esp32/nilpy-station-s3 --port /dev/ttyACM0
```

```text
wifi ap PXX-NILPY active True at 192.168.4.1
http listening on port 80
...
self-fetch / -> HTTP/1.1 200 OK page True
...
serving http://192.168.4.1/ from the hidden loop
http 127.0.0.1 GET /data HTTP/1.0
hidden loop: frame 16 self-fetch /data -> HTTP/1.1 200 OK requests 3
```

To see the page, **use the board plus a phone or laptop**: join `PXX-NILPY`
and open `http://192.168.4.1/`. The steps are in the header of
`main/main.npy`.

### How far it is tested

All of this was run on one ESP32-S3 board on 2026-09-25:

| What | On the board |
| --- | --- |
| `nilpy-station-s3` | all 12 lines of `main.expected`, the self-fetches included |
| socket errors and timeouts (`test/esp_board_socket_errors.npy`) | every line matches what CPython prints for the same calls on Linux, and nothing hangs |
| station (`test/esp_board_wifi_sta.npy`) | `active`, a `scan()` of the networks nearby with every record well formed, a `connect()` to a network that does not exist ending at `STAT_NO_AP_FOUND` within 30 seconds, and the access point and station together |

**Joining a real network has not been checked yet.** It needs a board and a
Wi-Fi network with its password. `test/esp_board_wifi_sta_join.npy` is the
recipe for it, with placeholders for the credentials. Nothing has been run on
an ESP32-C3.

The three snippets above compile for the ESP32-S3 with pin v426 (compiler
sha256 `7b742af6f9df…`) against the tree at `6ee238bc47`. The station half
of `network` landed after v426 was cut. It is library code only, so v426
compiles it.

## Files — `open()` and `os` on flash (Nil Python)

A Nil Python program on the ESP32 reads and writes files with Python's own
`open()` and `os`. The files live on the chip's flash, in a FAT filesystem
with wear levelling, in the partition table's `storage` partition.

**`/` is the root of that filesystem**, as on MicroPython. A relative path is
relative to it, and there is no `chdir`: `os.getcwd()` is always `/`. ESP-IDF
mounts the filesystem under a prefix of its own, but your program never sees
that prefix: not in a path you pass, not in `os.listdir()`, and not in an
error message.

```python
import os

f = open("/log.txt", "a")
f.write("boot\n")
f.close()

print(open("log.txt").read())        # a relative path: the same file
print(os.listdir("/"))
print(os.stat("/log.txt").st_size, os.path.isfile("/log.txt"))
if not os.path.isdir("/data"):
    os.mkdir("/data")
```

The filesystem is mounted the first time your program names a path, not at
boot. If the partition will not mount, as on a newly flashed board whose
partition is still blank, `pxx_fs` formats it then, as MicroPython does.

### What a project needs

The filesystem is **opt-in per project**. `examples/esp32/nilpy-station-s3`
has all three pieces, so copy from it:

- **the `pxx_fs` component**: `lib/rtl/platform/esp/idf` in
  `EXTRA_COMPONENT_DIRS` (its top-level `CMakeLists.txt`), and `pxx_fs` in
  `REQUIRES` (its `main/CMakeLists.txt`);
- **a `storage` row** in its `partitions.csv`;
- **the matching settings** in its `sdkconfig.defaults`.

**Without the `pxx_fs` component** the program still builds and links, but
it has no filesystem: every path answers `FileNotFoundError`
(`[Errno 2] No such file or directory`). That includes `/`.

### Errors

A failed file call raises the same `OSError` subclass as CPython on Linux,
with the same text, so `except FileNotFoundError:` works as it does on a PC:

```python
try:
    text = open("/config.json").read()
except FileNotFoundError:
    text = "{}"                      # first boot: no settings yet
except OSError as e:
    print("cannot read settings:", type(e).__name__, str(e))
    text = "{}"
print(text)
```

`test/esp_board_files.npy` provokes each case on the board. This is what the
board printed; each error line is the case, then the exception's class, then
`str(e)`:

```text
read back 'hello from flash\n'
size 17
isfile True isdir / True
listdir ['d', 'hello.txt']
open a missing file -> FileNotFoundError [Errno 2] No such file or directory: '/nope.txt'
open a directory -> IsADirectoryError [Errno 21] Is a directory: '/d'
create in a missing directory -> FileNotFoundError [Errno 2] No such file or directory: '/nodir/x.txt'
mkdir an existing directory -> FileExistsError [Errno 17] File exists: '/d'
stat a missing path -> FileNotFoundError [Errno 2] No such file or directory: '/nope.txt'
fill the partition -> OSError [Errno 28] No space left on device
after cleanup, write works True
listdir after []
ESP FILES OK
```

The rows up to `stat a missing path` print the same under CPython on a PC,
run against a scratch directory, apart from the directory's name. The
`No space left on device` row comes from writing until the partition is
full; after the file is removed, writing works again.

### How far it is tested

- On one ESP32-S3 board, with the `nilpy-station-s3` project:
  `test/esp_board_files.npy` matches all 13 lines above. The board test uses
  absolute paths; relative paths go through the same path mapping, but no board
  test checks them.
- A project **without** `pxx_fs` builds, links, and answers
  `FileNotFoundError` for every path, as described above.
- **Not tested:** a read-only partition, or any storage but the internal
  flash. There is **no `os.mount()`**, so an SD card or a second partition
  cannot be mounted from Python. Nothing has run on an ESP32-C3 board.

Both snippets compile for the ESP32-S3 with pin v427 (compiler sha256
`354cd45e6373…`), the first pin that carries the file support. The same
compile refuses `os.mount("/sd", "/sd")`.

For **Pascal** files on the ESP32, the C3 example `fs-c3` mounts FAT, writes,
seeks and reads back, under QEMU. See the
[examples showcase](../examples/index.md#esp32).

## Math errors do not stop the chip

An embedded device should keep running when a sensor produces a value that
causes a math error, so on the ESP32 family:

- integer `div` and `mod` by zero give 0 (Pascal and C), and `//` and `%` by
  zero give 0 (Nil Python);
- a float division by zero gives Inf or NaN;
- nothing halts the program.

On a desktop target the same integer division stops the program with runtime
error 200. [Known issues](../reference/known-issues.md#by-design-math-errors)
has the full table as measured on v425. If a zero divisor must stop your ESP
program, test the divisor yourself.

## Next

- [Getting started on the ESP32](../getting-started/esp32.md): setting up
  ESP-IDF and building a first program.
- [ESP32](../targets/esp32.md): the two build modes, code size and floating point.
- [Examples showcase](../examples/index.md#esp32): the ESP examples and their outputs.
- [Known issues in beta 0.1](../reference/known-issues.md)
