---
track: A
prio: 45
type: bug
blocked-by: []
summary: "With --target=riscv32 --platform=esp (ESP-IDF, whose libc is newlib + gcc's own headers), the crtl magic link still pulls lib/crtl headers and sources into the translation unit. crtl's stddef.h is LP64 (`typedef long ptrdiff_t`, `unsigned long size_t`) and collides with gcc's ilp32 one (`int` / `unsigned int`). After the four census fixes at fe4e8acb2d, that's now the first error for esp_wifi, esp_netif, esp_event, nvs_flash, nvs, esp_timer, esp_system (ptrdiff_t) and esp_task_wdt (size_t). Separately, crtl/src/string.c gets pulled by a plain `#include <stddef.h>` and fails on NULL. Measured 2026-10-05, frank-user master fe4e8acb2d."
status: done
owner: ""
---

# ESP-IDF C import pulls crtl headers and sources beside newlib

- **Type:** bug (C preprocessor / magic link per platform) — **Track A**.
- **Filed:** 2026-10-05 from `~/museum_landkaart`, the ESP-IDF census after #1-#4.

## Repro 1: the real one

From ~/museum_landkaart/async (needs ./build.sh esp once for compile_commands):

```sh
tools/idf_census.sh esp_timer esp_task_wdt
# esp_timer:    pascal26:160: error: conflicting types for typedef 'ptrdiff_t' — a repeated typedef must name the same type
#               in: .../lib/gcc/riscv32-esp-elf/15.2.0/include/stddef.h   near: typedef int ptrdiff_t
# esp_task_wdt: pascal26:5: error: conflicting types for typedef 'size_t'
#               in: /home/neo/frank-user/compiler/../lib/crtl/include/stddef.h   near: typedef unsigned long size_t
```

Same flags with `--dump-cpp` on `#include "esp_timer.h"`: the line markers show
`TC/riscv32-esp-elf/include/sys/cdefs.h` (newlib) line 44 `#include <stddef.h>`
resolving to `# 1 ".../lib/crtl/include/stddef.h"`, even though gcc's
`lib/gcc/riscv32-esp-elf/15.2.0/include/` (which has stddef.h) is earlier on the -I
list. crtl is the last search root. gcc's stddef.h had already been included
earlier in the TU.

I couldn't reduce this outside IDF. These all resolve correctly to the -I copy:
`<stddef.h>` vs `"stddef.h"`, with and without -nostdinc, from a file reached via
#include_next, double inclusion with a plain #ifndef guard, double inclusion of
gcc's real stddef.h with and without `__need_size_t`. So the trigger is somewhere
in your resolver's crtl-pull path ("slots hidden by a crtl pull"), which you can
read directly.

`CENSUS_EXTRA=-nostdinc tools/idf_census.sh esp_timer` instead fails with
`C include file not found: "stddef.h"`, although gcc's include dir is on the
printed search list. So a crtl-only lookup with no -I fallback happens there too.

## Repro 2: crtl sources pulled into an ESP-IDF program

```sh
mkdir g1 && cp ~/.espressif/tools/riscv32-esp-elf/*/riscv32-esp-elf/lib/gcc/riscv32-esp-elf/15.2.0/include/stddef.h g1/
printf '#include <stddef.h>\nint main(void){ return 0; }\n' > r.c
pascal26 --target=riscv32 --platform=esp -Ig1 --no-signals --emit-obj r.c r.o
# error: undeclared identifier 'NULL' used as value
#   in: .../lib/crtl/src/string.c   near: return NULL
pascal26 -Ig1 r.c rx     # x86-64: compiles
```

## Expected

On --platform=esp, the C side has a real libc (newlib, linked by IDF), so the magic
link should be off: no crtl header pulls and no crtl source pulls, and
`<header>` resolves by the -I list alone (gcc's order). Or crtl must at least
match the target's type sizes, but pulling crtl sources into an IDF link would
duplicate newlib symbols anyway.

## Acceptance

`tools/idf_census.sh esp_wifi esp_netif esp_event nvs_flash nvs esp_timer
esp_system esp_task_wdt` gets past the stddef typedefs, and repro 2 compiles.

## Resolution (2026-10-05)

Two causes, neither in the crtl-pull path:

1. **pxx bug, fixed:** `#include_next` (7e8188d2bd) left its start index set
   while the file it found was processed, so every plain `#include` nested
   inside it skipped the dirs before that point. gcc's stdint.h →
   include_next → newlib's stdint.h → sys/cdefs.h `#include <stddef.h>`
   therefore skipped gcc's include dir and fell through to crtl's.
   The search start now resets as soon as the include_next search is done.
   The test-core include_next row covers the nested case (116 with the bug,
   17 without).
2. **census include order:** this project is built with
   `CONFIG_LIBC_PICOLIBC=y`, so gcc's real order is `picolibc/include`, then
   gcc `include`, `include-fixed`, then newlib
   (`riscv32-esp-elf-gcc --specs=picolibc.specs -E -v`). With newlib's dir
   alone, IDF's `sys/reent.h` (`#if CONFIG_LIBC_NEWLIB ... #include_next`)
   leaves `__FILE` undefined, and stdio.h's `FILE` follows.

Repro 2 (a C program pulling crtl's string.c) is by design. crtl is the libc
unless `--system-libs` says another one is. `--system-libs` turns the impl
pulls off and repro 2 compiles. The ESP C-conformance runner uses crtl as its
libc under the IDF profile, so the default is not flipped for --platform=esp.

With the fixes in this commit and picolibc first on -I, all nine census
headers import: esp_wifi esp_netif esp_event nvs_flash nvs esp_timer
esp_system esp_task_wdt esp_sntp.
