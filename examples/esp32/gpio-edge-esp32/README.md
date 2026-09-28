# NilPy GPIO edge callbacks on the classic ESP32 (Xtensa LX6)

`examples/esp32/gpio-edge-c3` and `gpio-edge-s3` on the third chip. The program,
its expected output and the build script are **symlinks** to the C3 project, so
all three chips compile the same source and cannot drift apart:

```text
build.sh           -> ../nilpy-c3/build.sh
main/main.npy      -> ../../gpio-edge-c3/main/main.npy
main/main.expected -> ../../gpio-edge-c3/main/main.expected
```

```sh
. ~/esp/esp-idf/export.sh
cd examples/esp32/gpio-edge-esp32
./build.sh
```

On a board, from the repo root:

```sh
tools/esp_flash.sh --project examples/esp32/gpio-edge-esp32 --port /dev/ttyUSB0
```

## Why this port exists, beyond covering a third chip

It is a **discriminator** for the LX6-only failure recorded in
`examples/esp32/nilpy-hw-esp32/README.md`, where that project watchdog-loops in
`_xt_context_save` on this chip while matching its oracle on real S3 and C3
silicon. Two things differ between these two projects, and nothing measured so
far separates them:

| | `gpio-edge-esp32` | `nilpy-hw-esp32` |
| --- | --- | --- |
| IDF components | `esp_timer esp_driver_gpio lwip esp_netif` | the same **plus** `esp_driver_spi esp_driver_i2c esp_driver_rmt pxx_tls` |
| what the program does | NilPy, `espgpio` + interrupts | NilPy, `espgpio` + an `esp_timer` callback into Pascal |

Both are static Python programs that touch hardware through pxx's own Pascal
units, so they share the NilPy hardware path. They differ in four extra
components.

### The answer, measured 2026-09-28: it loops too

Compiler `b2b325036c3b`, ESP32-D0WD-V3 over the CP2102:
`esp_flash: FAIL -- the board rebooted during the capture (15 ROM reset lines)`,
with the PRO CPU stopped at the same place every cycle:

```text
W boot.esp32: WDT rst info: PRO CPU PC=0x4008ae38
W boot.esp32: WDT rst info: APP CPU PC=0x40080340
```

Resolved against this project's own map:

| | PRO CPU PC | resolves to |
| --- | --- | --- |
| `gpio-edge-esp32` | `0x4008ae38` | inside **`_xt_context_save`** (starts `0x4008ad98`) |
| `nilpy-hw-esp32` | `0x4008b13c` | inside **`_xt_context_save`** (starts `0x4008b09c`) |

Two different images, two different addresses, **the same function**. The APP CPU
sits at `_UserExceptionVector` and `xt_debugexception`, so it is taking exceptions
as well.

**So the four extra components are exonerated.** This project requires only
`esp_timer esp_driver_gpio lwip esp_netif` and fails identically. The fault is in
what these two programs share, not in `esp_driver_spi/i2c/rmt` or `pxx_tls`.

### What the pair now narrows it to, and what it does not

Four LX6 results, all on the same board with the same compiler:

| program | shape | LX6 |
| --- | --- | --- |
| `nilpy-esp32` | NilPy, no hardware, no callback | **PASS** (4-line oracle) |
| `timer-esp32` | **Pascal**, `esp_timer` callback | **PASS** (7-line oracle) |
| `gpio-edge-esp32` | NilPy, `espgpio` + a callback | **loops in `_xt_context_save`** |
| `nilpy-hw-esp32` | NilPy, `espgpio` + a callback | **loops in `_xt_context_save`** |

The common factor in the two failures is a **NilPy** program that takes a
callback from C into compiled code while using `espgpio`. Plain NilPy is fine on
this chip, and a callback into **Pascal** is fine on this chip, so neither NilPy
nor callbacks alone explain it.

What is still NOT separated: whether the trigger is `espgpio` specifically, or any
C-to-NilPy callback. Nothing measured distinguishes those, and the next cheap
experiment is a NilPy program that takes an `esp_timer` callback with no GPIO at
all. Until someone runs it, both remain open — and this file will not pretend
otherwise.

## Scope

The owner's settled ESP scope is the **S3 and C3**. The classic ESP32 is **proven
where run, not promised**, and this project is here for the diagnosis above as
much as for the coverage.
