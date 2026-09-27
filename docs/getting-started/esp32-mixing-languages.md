---
title: Mixing languages on the ESP32
order: 33
---

# Mixing languages on the ESP32

PXX compiles Pascal, C and Nil Python with one compiler into one program, so
on the ESP32 a Python program can call a Pascal unit, and a Pascal program can
call C, with no binding code in between. This page shows both on an ESP32-C3.

**What was checked.** With pin v445 (compiler sha256 `caf21ac399f1`) on
2026-09-27, in a fresh clone at `025a005851`, with ESP-IDF v6.0.1: both
programs below built through ESP-IDF to a C3 image, and both ran under
Espressif's QEMU for the ESP32-C3 and printed exactly what the same source
prints on a PC. They have not been run on a board.

## Nil Python calling a Pascal unit

A filter written in Pascal, `filters.pas`:

```pascal
unit filters;
{ A moving-average filter, written in Pascal, used from Nil Python. }
interface
function Smooth(prev, sample, weight: Integer): Integer;
function Describe(v: Integer): AnsiString;
implementation
uses sysutils;
function Smooth(prev, sample, weight: Integer): Integer;
begin
  Result := (prev * (weight - 1) + sample) div weight;
end;
function Describe(v: Integer): AnsiString;
begin
  if v > 3000 then Result := 'high (' + IntToStr(v) + ')'
  else Result := 'normal (' + IntToStr(v) + ')';
end;
end.
```

and the Python program that uses it, `main.npy`. A Pascal unit is imported by
its file name, with `as` to give it a name:

```python
import 'filters.pas' as f

level = 0
for sample in [3900, 3880, 3910, 1200, 1180]:
    level = f.Smooth(level, sample, 2)
    print(sample, "->", f.Describe(level))
```

Pascal's `Integer` arrives as a Python `int` and `AnsiString` as a `str`; nothing
converts them by hand. The output, on the PC and on the emulated C3 alike:

```text
3900 -> normal (1950)
3880 -> normal (2915)
3910 -> high (3412)
1200 -> normal (2306)
1180 -> normal (1743)
```

To build it, make a project from `nilpy-c3` inside `examples/esp32/` and put
both files in its `main/` folder:

```sh
cd examples/esp32
cp -rL nilpy-c3 xpy-c3
rm -rf xpy-c3/build xpy-c3/main/main.expected
cp /path/to/main.npy /path/to/filters.pas xpy-c3/main/
. ~/esp/esp-idf/export.sh
xpy-c3/build.sh               # build only; the image was 1,418,624 bytes
```

With the program's expected output saved as `xpy-c3/main/main.expected`,
`xpy-c3/build.sh qemu-assert` boots it under QEMU and compares. It printed
`OK xpy-c3 -- ... output == main/main.expected, one boot`.

The ESP units themselves work the same way: `import 'espgpio.pas' as gpio` in
[Getting started on the ESP32](./esp32.md#4-a-python-program) is a Pascal unit
imported from Python.

## Pascal calling C

A CRC-8 routine in C, `crc8.c`, with its header `crc8.h`:

```c
#ifndef CRC8_H
#define CRC8_H
unsigned char crc8(const unsigned char *data, int len);
#endif
```

```c
#include "crc8.h"
unsigned char crc8(const unsigned char *data, int len) {
    unsigned char crc = 0;
    for (int i = 0; i < len; i++) {
        crc ^= data[i];
        for (int b = 0; b < 8; b++)
            crc = (crc & 0x80) ? (unsigned char)((crc << 1) ^ 0x07) : (unsigned char)(crc << 1);
    }
    return crc;
}
```

The Pascal program names the C file in its `uses` clause. PXX compiles
`crc8.c` with its own C frontend, and `crc8` is then callable like a Pascal
function:

```pascal
program crcdemo;
{ A C function, compiled from crc8.c by the same compiler, called from Pascal. }
uses './crc8.c';
var
  msg: AnsiString;
begin
  msg := '123456789';
  writeln('crc8("', msg, '") = ', crc8(PByte(msg), Length(msg)));
end.
```

It prints `crc8("123456789") = 244`, which is `0xF4`, the published check
value for this CRC. To build it, make a project from `hello-c3` and put the
three files in its `main/` folder:

```sh
cd examples/esp32
cp -rL hello-c3 xpas-c3
rm -rf xpas-c3/build
cp /path/to/main.pas /path/to/crc8.c /path/to/crc8.h xpas-c3/main/
. ~/esp/esp-idf/export.sh
xpas-c3/build.sh              # build only; the image was 187,376 bytes
```

To run it under QEMU instead, without a project of your own:

```sh
ESP_RUN_PXX=stable_linux_amd64/default/pinned tools/esp_run.sh --chip esp32c3 /path/to/main.pas
```

`tools/esp_run.sh` compiles with `compiler/pascal26` unless `ESP_RUN_PXX`
names another compiler (not `PXX`), and prints which one it used.

## What this does not cover

- **ESP-IDF's own C headers** (`driver/gpio.h` and the rest) were not included
  from Pascal or Python for this page. The ESP units reach ESP-IDF through
  `external` declarations instead; see [ESP32 peripherals](../library/esp.md).
- **Calling Python from Pascal or C** is not shown here.
- How names are looked up when two languages define the same one is in
  [Name resolution](../language/name-resolution.md) and
  [Name collisions](../language/name-collisions.md).
