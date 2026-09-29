---
title: Mixing languages on the ESP32
order: 33
---

# Mixing languages on the ESP32

PXX compiles Pascal, C and Nil Python with one compiler into one program, so
on the ESP32 a Python program can call a Pascal unit, and a Pascal program can
call C, with no binding code in between. This page shows both on an ESP32-C3;
the Python example also runs on an emulated ESP32-S3.

**What was checked.** With [pin](../reference/glossary.md#terms-in-the-release-notes-and-the-esp-pages) v445 (compiler sha256 `caf21ac399f1`) on
2026-09-27, in a fresh clone at `025a005851`, with ESP-IDF v6.0.1: both
programs below built through ESP-IDF to a C3 image, and both ran under
Espressif's QEMU for the ESP32-C3 and printed exactly what the same source
prints on a PC. On 2026-09-28 both also ran on a real ESP32-C3 board (rev
v0.4), built exactly as below with the compiler of tree `cdd6fd3c1f` (sha256
`139494b2b863`), through `tools/esp_flash.sh --project`. The Python program's
five lines matched its `main.expected`, and the Pascal program printed
`crc8("123456789") = 244`. The board booted once in each run. On 2026-09-28
every command on this page was run again as written, with pin v448 (sha256
`b2b325036c3b`) in a fresh clone at `6b34caaf23`: both projects built, the
Python one passed `qemu-assert`, and the Pascal one printed the line above
under QEMU through `tools/esp_run.sh`. That run found the QEMU command below
failing with a relative compiler path; it now gives an absolute one. On
2026-09-29 the page was walked again from an unpacked archive of pin v451
(sha256 `d9b7226769cc`), with ESP-IDF v6.0.1 already installed: both
Python projects passed `qemu-assert` on the C3 and the S3, and the Pascal
program printed its line under QEMU. The QEMU line for a checkout does not
work in an archive; the section below gives the one that does.

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
xpy-c3/build.sh               # build only; the image was 1,459,728 bytes (v451)
```

With the program's expected output saved as `xpy-c3/main/main.expected`,
`xpy-c3/build.sh qemu-assert` boots it under QEMU and compares. It printed
`OK xpy-c3 -- ... output == main/main.expected, one boot`.

For an ESP32-S3, copy `nilpy-s3` instead of `nilpy-c3` (to `xpy-s3`) and use
the same files. With pin v450 on 2026-09-29 it built (the image was 1,342,912
bytes) and `xpy-s3/build.sh qemu-assert` printed `OK xpy-s3 -- ... output ==
main/main.expected, one boot` with the output shown above. With pin v451 from
an unpacked archive the image was 1,373,000 bytes, and the result the same.

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
xpas-c3/build.sh              # build only; the image was 187,392 bytes (v448)
```

To run it under QEMU instead, without a project of your own, from the top of
the PXX directory. In an unpacked release archive:

```sh
tools/esp_run.sh --chip esp32c3 /path/to/main.pas
```

In a git checkout, name the pinned compiler, because a checkout has no
`compiler/pascal26` until you build one:

```sh
ESP_RUN_PXX=$PWD/stable_linux_amd64/default/pinned tools/esp_run.sh --chip esp32c3 /path/to/main.pas
```

An archive has no `stable_linux_amd64/`. With the `tools/esp_run.sh` of pin
v451 or earlier, the second line stops there with `esp_run: compiler
.../stable_linux_amd64/default/pinned not found or not executable`, so use
the first. The script in the repository now falls back to the archive's
`compiler/pxx-x86_64` and says so. With pin v451 from an unpacked archive on
2026-09-29, the first line printed `crc8("123456789") = 244` after about a
minute, with nothing printed while it built. That was with its `hello-c3`
project already built once; the first run takes 2 to 3 minutes.

`tools/esp_run.sh` compiles with `compiler/pascal26` unless `ESP_RUN_PXX`
names another compiler (not `PXX`), and prints which one it used. The script
compiles from inside a staged ESP-IDF project. Since 2026-09-28 it resolves a
relative `ESP_RUN_PXX` against the directory you run it from, and stops with
`esp_run: compiler ... not found or not executable` if nothing is there. An
older copy of the script needs the absolute path, as above: given a relative
one, it stops with `No such file or directory` and `compiling ... failed`.

## What this does not cover

- **ESP-IDF's own C headers** (`driver/gpio.h` and the rest) were not included
  from Pascal or Python for this page. The ESP units reach ESP-IDF through
  `external` declarations instead; see [ESP32 peripherals](../library/esp.md).
- **Calling Python from Pascal or C** is not shown here.
- How names are looked up when two languages define the same one is in
  [Name resolution](../language/name-resolution.md) and
  [Name collisions](../language/name-collisions.md).
