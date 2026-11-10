---
slug: feature-code-size-int64-arith-and-string-building
track: S
type: feature
prio: 50
status: backlog
owner: ""
created: 2026-10-31
found-by: claude (remote_thermostat, app slots 91-95% full)
blocked-by: []
summary: "Real-app routines are 5-15x the size of the same C: 64-bit integer arithmetic (BMP280 compensation, 6 lines -> 3.5 KB; 12 lines -> 6.5 KB) and string building/parsing (config parse 17.8 KB, config to text 15.2 KB, JSON 9.3 KB). The project's 1.25 MB OTA slots are 91% (C3) and 95% (S3 meter) full; pxx code is 56% of the image."
---

# Code size: Int64 arithmetic and string building in a real app

remote_thermostat (~/remote_thermostat) is nearly out of app-slot space on
4 MB boards. The IDF side is already trimmed (no IPv6/WPA3/TLS, warn-level
logs); what grows is the pxx code. Not asking for new features: the project
mostly needs its existing code smaller. The RVC ticket
(feature-riscv32-emits-no-compressed-rvc-instructions) is still the largest
single item on the C3; this ticket is about what is big on every target.

## Numbers (2026-10-31, stable pinned compiler, esp32c3, `./build.sh esp`)

Image 1,202,512 B of a 1,310,720 B slot; libpxx_app.a 659 KB (code
607,664 B, data 44,308 B). Routine sizes from `objdump -t esp/main/main.o`
(symbol address gaps in .text):

| routine (unit)            | bytes  | what it is                                         | C estimate |
|---------------------------|--------|----------------------------------------------------|------------|
| BmpTemp (src/tbmp.pas)    | 3,564  | 6 lines of Int64 mul/shift (Bosch datasheet 4.2.3) | ~150       |
| BmpPress (src/tbmp.pas)   | 6,536  | 12 lines of Int64 mul/shift, one Int64 div         | ~400       |
| BmpStatus (src/tbmp.pas)  | 3,544  | one status string from 6 pieces                   | ~200       |
| ConfigParse (src/tconfig) | 17,792 | key/value text -> record, ~60 keys                 | ~3,000     |
| ConfigToText (src/tconfig)| 15,244 | record -> key/value text, ~60 lines                | ~2,000     |
| StateJson (src/tbrain)    | 9,324  | ~60 JSON fields via one-call helpers               | ~2,500     |
| NextHop (src/tnow)        | 8,688  | Dijkstra on 17 nodes + parse "mac:rssi,..."        | ~800       |

Runtime helpers that dominate the "(pxx runtime)" share (68 KB in all):
PXXStrSetLen 5,008; PXXDynArrayReleaseDepth 4,848; PXXStrAppend 4,272;
PXXArrayReleaseImmediate 3,724; PXXRecordRelease 3,168; PXXRecordRetain
2,892; PXXStrConcat 2,804; PXXObjRelease 2,756; PXXTIOGetInterface 2,712
(the app has no interfaces or objects: dead-strip candidates?).

## Likely causes (to confirm)

- Int64 ops on rv32 expanded inline each time (mul, shifts with variable
  count, compare) rather than one shared helper call per op; tbmp's `Sar`
  (shr on a negative Int64) is inlined at every use.
- String temporaries: each `a + b + IntStr(x)` chain materialises and
  releases managed temporaries per step; ConfigToText is ~60 such lines.
- Runtime helpers for interfaces / objects / dyn arrays linked in though
  unused.

## Reproduce

    cd ~/remote_thermostat && ./build.sh esp     # CHIP=esp32c3 default
    riscv32-esp-elf-objdump -t esp/main/main.o   # sizes: next symbol - this one

Per-unit totals (C3): tbrain 99 KB, pxx runtime 68, trelay 65, tnow 63,
tconfig 61, thttp 28, twifi 26, tutil 25, tbridge 25, thw 22, tbmp 21,
tota 18, trtc 14.

## Current-state audit (2026-11-09)

Keep open, but remeasure before using the opening numbers as a current baseline.
Several proposed improvements have landed: RV32C (a7a06dd208), concat-chain
lowering (d06d3045c0), small-constant Int64 addition/subtraction (5b53d37074),
32-bit div/mod fast paths (b1173cb992), and bulk Copy/Delete/Insert
(d1a3dc081d). The existing dirty checkout additionally contains uncommitted
constant-64-bit-shift and inline-literal-substitution changes; these are not a
landed fix. The RVC ticket is now in done/ after ten hosted differential/size
checks. None of those checks remeasures remote_thermostat's linked image,
per-routine sizes, or OTA headroom, so they do not close this broader ticket.

## Remeasured 2026-11-10 (constant shifts + literal inline arguments)

feature-rv32-constant-64-bit-shifts-and-literal-inline-arguments landed:
code 280,930 -> 277,562 B on the app as it is today (data/bss unchanged).
BmpTemp 1,804 -> 1,028, BmpPress 3,276 -> 1,976 (opening numbers: 3,564 and
6,536). Not yet remeasured: the linked image and OTA headroom.
