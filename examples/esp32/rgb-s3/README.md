# PXX ESP32-S3 RGB fade

A rainbow colour fade on the ESP32-S3 devkit's onboard WS2812 RGB LED, written
in Pascal and compiled by pxx (`--target=xtensa --xtensa-abi=windowed`). The
WS2812 is driven through IDF's RMT peripheral and bytes encoder, called
directly from Pascal. There is no C wrapper.

The LED is on GPIO48 on DevKitC-1 v1.0 and GPIO38 on v1.1, so the demo drives
both. Edit `pins[]` in `main/main.pas` if your board has only one of them.

```sh
. ~/esp/esp-idf/export.sh
tools/esp_flash.sh --project examples/esp32/rgb-s3 --no-verify   # from the repo root
```

If the board has two USB connectors, use the USB-UART bridge one (here a
CH343, `1a86:55d3`): it stays connected through a chip reset, and its DTR/RTS
lines drive EN/BOOT, so flashing and reading output work without the gaps the
chip's own USB port has (below).

Expected serial output:

```
PXX rgb: WS2812 channel up on GPIO48
PXX rgb: WS2812 channel up on GPIO38
PXX rgb: rainbow cycle 1
...
```

Verified on silicon 2026-09-24: ESP32-S3 (QFN56) rev v0.2, 16 MB flash,
8 MB PSRAM, built with the pinned compiler and flashed through the chip's
native USB-Serial/JTAG port.

That port belongs to the chip itself, so every reset disconnects it. On that
host, after esptool reset the board over USB, the port took about 90 s
to come back (`device descriptor read/64, error -110`) while the LED was
already fading. It came back without a replug. A capture started during that
gap reads nothing, and `esp_flash.sh` reports "the board said nothing". Devkits
with a second USB connector (a USB-UART bridge on UART0, GPIO43/44, the
primary console) show the same output on `/dev/ttyUSB*`, and that port stays
connected through a chip reset.

## Edit-compile-upload loop, measured 2026-09-24

Pinned pxx, IDF v6.0.1, CH343 port, busy 12-core host. Min of 5 (compile,
link) or 3 (upload, full chain):

| stage | time |
|---|---|
| pxx compile `main.pas` + `ar` | 0.38 s |
| IDF relink (`.elf` + `.bin`) | 2.2 s |
| upload bootloader + table + app @ 921600 | 4.5 s |
| **full chain, compile start to upload done** | **7.1 s** |

Before `main/CMakeLists.txt` switched to a non-global imported target, the
full chain took 25.0 s. Each recompile made IDF's ldgen regenerate
`sections.ld`, and ldgen spent ~18 s using pyparsing to re-read 63 IDF
fragment files and the section tables of 17 IDF archives. None of those are
our archive, and the output was byte-identical every time. Upload is mostly
fixed cost: going from 921600 to 2000000 baud saves about 0.1 s.
