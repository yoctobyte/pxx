# Licensing

pxx is licensed per directory. Every source file
carries a one-line `SPDX-License-Identifier` header; this table is the map.

| Path | License | Text |
| --- | --- | --- |
| `compiler/**` (except `compiler/builtin/`) | MPL 2.0 | [LICENSE](LICENSE) |
| `tools/**` | MPL 2.0 | [LICENSE](LICENSE) |
| `compiler/builtin/**`, `lib/rtl/**`, `lib/pcl/**`, `lib/crtl/**`, `lib/asmcore/**` | zlib | [licenses/Zlib.txt](licenses/Zlib.txt) |
| `examples/**` | 0BSD | [licenses/0BSD.txt](licenses/0BSD.txt) |
| `docs/**` | CC BY 4.0 | <https://creativecommons.org/licenses/by/4.0/> |
| everything else (tests, devdocs, build files) | MPL 2.0 | [LICENSE](LICENSE) |

Why the split: the runtime and libraries under zlib are **embedded into every
binary the compiler produces** — programs you compile with pxx are
entirely yours, with no license obligations from the toolchain. The compiler
itself is MPL 2.0: use it anywhere, link it with anything, but published
modifications to its files stay open.

## Compiled output

Binaries produced by the compiler belong to their author. The runtime code
embedded in them is zlib-licensed, which imposes no requirements on binary
distribution, except for the files listed under *Files under other licences*
below, when a program contains them.

## Contributions

External contributions require a Developer Certificate of Origin sign-off
(`git commit -s`) and include a contributor license grant that permits the
project to relicense contributed code if the project license ever needs to
change; see [CONTRIBUTING.md](CONTRIBUTING.md).

## Files under other licences

These runtime files do not carry the licence of their directory. Each holds
its licence text in its own header.

| file | licence | origin | in a program when |
| --- | --- | --- | --- |
| `lib/rtl/platform/esp/espmpyport.pas` | MIT, Copyright (c) 2013-2017 Damien P. George | MicroPython v1.26.1, translated to Pascal | an ESP32 Nil Python program calls `machine.time_pulse_us`, reads a DHT sensor or uses 1-Wire |
| `lib/rtl/mimic_framebuf_font.py` | MIT, Copyright (c) 2013, 2014 Damien P. George | MicroPython v1.26.1, `extmod/font_petme128_8x8.h` | a Nil Python program uses `framebuf` |
| `lib/crtl/include/fenv.h`, `lib/crtl/src/fenv.c` | MPL 2.0 | written in this repository | a C program includes `<fenv.h>`; `fenv.c` is in every C program built for wasm32 |

MIT: keep the copyright and permission notice with copies of the software.
MPL 2.0: file-level copyleft; modified versions of those files must stay
available under MPL 2.0, and the rest of a program is unaffected. The two
MicroPython files are also listed in `lib/rtl/THIRD-PARTY.md`.

## Third-party code

Apart from the two MicroPython files above, the repository contains no
third-party code. Optional external material
(the Lua test corpus, library candidate sources fetched by
`tools/install_lib_candidates.sh`) is downloaded locally on demand, lives in
git-ignored directories, and keeps its own upstream licenses.

## No warranty

The software is provided "as is", without warranty of any kind. It is under
active development; see each license text for the full disclaimer.
