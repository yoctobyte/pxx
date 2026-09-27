---
title: Licensing
order: 95
---

# Licensing

PXX is open source, licensed **per directory**. Every source file carries a
one-line `SPDX-License-Identifier` header; the table below is the map. The
authoritative copy lives in
[`LICENSE.md`](https://github.com/yoctobyte/pxx/blob/master/LICENSE.md) at the
repository root.

| Path | License |
| --- | --- |
| `compiler/**` (except `compiler/builtin/`) | MPL 2.0 |
| `tools/**` | MPL 2.0 |
| `compiler/builtin/**`, `lib/rtl/**`, `lib/pcl/**`, `lib/crtl/**`, `lib/asmcore/**` | zlib |
| `examples/**` | 0BSD |
| `docs/**` | CC BY 4.0 |
| everything else (tests, devdocs, build files) | MPL 2.0 |

## Why the split

The runtime and libraries — everything under the **zlib** license — are
**embedded into every binary the compiler produces**. Because zlib carries no
attribution or copyleft obligation, programs you compile with PXX are yours:
the toolchain adds no license strings to your output. Four runtime files are
the exception, and only for programs that use them; see
[below](#files-under-other-licences-embedded-in-programs).

The compiler itself is **MPL 2.0**: use it anywhere, link it with anything, ship
products built with it — but published modifications to the compiler's own source
files stay open under the same license. MPL's copyleft is file-scoped, so it does
not reach into code you merely compile or link against.

Examples are **0BSD** (public-domain-equivalent, no attribution required) so you
can lift a demo into your own project without ceremony. These documentation
pages are **CC BY 4.0**.

## What this means for you

- **Programs you build with PXX:** the embedded runtime is zlib-licensed and
  imposes nothing on your binary, except for the four files listed in the
  next section, when your program contains them.
- **Shipping the compiler or a modified compiler:** MPL 2.0 applies. You may
  distribute it commercially; you must make source for any modified MPL files
  available under MPL.
- **Reusing example code:** 0BSD — copy freely, no attribution needed.
- **Reusing these docs:** CC BY 4.0 — reuse with attribution.

## Files under other licences embedded in programs

Four runtime files do not carry the zlib licence of their directory. Each is
compiled into a program only when that program uses it. What their licences
ask is summarised below; the licence text in each file is the binding term.

**Third-party code, MIT licence.** Both files come from MicroPython,
<https://github.com/micropython/micropython>, v1.26.1, commit
`647c8b96cae7e202c7a020395b7cfe65e5b8ce04`. They are listed with their origin
in `lib/rtl/THIRD-PARTY.md`, and each file's header holds the full MIT text.

| file | what it is | when a program contains it |
| --- | --- | --- |
| `lib/rtl/platform/esp/espmpyport.pas` | MicroPython's microsecond pin protocols (`time_pulse_us`, the DHT read, the 1-Wire bus and its CRC), translated line for line into Pascal. Copyright (c) 2013-2017 Damien P. George. | a Nil Python program for the ESP32 that calls `machine.time_pulse_us`, reads a DHT sensor or uses a 1-Wire bus (measured with pin v445: `import machine` with only `Pin` does not bring it in) |
| `lib/rtl/mimic_framebuf_font.py` | MicroPython's 8x8 font (`extmod/font_petme128_8x8.h`), transcribed row for row. Copyright (c) 2013, 2014 Damien P. George. | a Nil Python program that uses `framebuf` |

The MIT licence asks that its copyright notice and permission notice be
included in all copies or substantial portions of the software. If you
distribute a program that contains either file, include those notices with
it; they are in the file headers.

**This project's own code, MPL 2.0.** `lib/crtl/include/fenv.h` and
`lib/crtl/src/fenv.c`, C's rounding-mode functions (`fesetround`,
`fegetround`), were written in this repository. Their headers say MPL-2.0,
unlike the zlib licence the table gives `lib/crtl`. `fenv.h` is read by a C
program that includes `<fenv.h>`. `fenv.c` is compiled into C programs built
for wasm32: a plain C hello for wasm32 contains `__pxx_fegetround` (measured
with pin v445). MPL 2.0 is file-level copyleft. If you distribute a program
containing these files and you modified them, the source of your modified
versions of those files must stay available under MPL 2.0. The rest of your
program is not affected.

This is informational, not legal advice; the license texts in the repository
(`LICENSE`, `licenses/Zlib.txt`, `licenses/0BSD.txt`) are the binding terms.

## Next

- [Command line](./cli.md)
- [Current limits](./limits.md)
