# Third-party code and data in lib/rtl

Almost all of lib/rtl is written in this tree and carries its own SPDX line.
The files below are taken from elsewhere. Each keeps its upstream copyright
and licence text in its own header, and this list records where it came from.

| file | what | upstream | version | licence |
| --- | --- | --- | --- | --- |
| mimic_framebuf_font.py | the 8x8 font that `framebuf.FrameBuffer.text()` draws, transcribed row for row from `extmod/font_petme128_8x8.h` | https://github.com/micropython/micropython | v1.26.1, commit 647c8b96cae7e202c7a020395b7cfe65e5b8ce04 | MIT, Copyright (c) 2013, 2014 Damien P. George |
| platform/esp/espmpyport.pas | MicroPython's microsecond pin protocols -- `machine.time_pulse_us`, `dht_readinto` and the `_onewire` bus and CRC -- translated line for line into Pascal from `extmod/machine_pulse.c`, `drivers/dht/dht.c` and `extmod/modonewire.c` | https://github.com/micropython/micropython | v1.26.1, commit 647c8b96cae7e202c7a020395b7cfe65e5b8ce04 | MIT, Copyright (c) 2013-2017 Damien P. George |

The MIT licence text for each entry is reproduced in full in that file's header.
