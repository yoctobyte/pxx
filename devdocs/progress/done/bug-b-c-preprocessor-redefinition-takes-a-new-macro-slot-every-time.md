---
track: A
prio: 45
type: bug
blocked-by: []
summary: "The C preprocessor gives every #define a fresh slot in the macro table, even an identical redefinition or a #define after #undef. 40000 copies of '#define A 1' fail with 'too many C macros' (MAX_CPREP_MACROS=32768), while 30000 DISTINCT macros compile. ESP-IDF headers redefine heavily, so FreeRTOS's riscv portmacro.h (3576 macros per gcc -dM) overflows the table, and with it every IDF header that includes FreeRTOS (esp_wifi.h, esp_event.h, esp_netif users, nvs, sntp, task_wdt...). Measured 2026-10-05, frank-user master 804851ea40, compiler/pascal26."
status: done
owner: ""
---

# C preprocessor: a redefinition takes a new macro slot every time

- **Type:** bug (C preprocessor, compiler/cpreproc.inc) — **Track A**.
- **Filed:** 2026-10-05 from `~/museum_landkaart`, the ESP-IDF header-import census
  (pxx agent plan item A follow-up).

## Repro (no IDF needed)

```sh
python3 -c "open('redef_same.c','w').write('#define A 1\n'*40000+'int main(void){return A;}\n')"
python3 -c "open('undef_def.c','w').write('#undef A\n#define A 1\n'*40000+'int main(void){return A;}\n')"
python3 -c "open('distinct.c','w').write(''.join('#define M%d %d\n'%(i,i) for i in range(30000))+'int main(void){return M5;}\n')"
for f in redef_same undef_def distinct; do pascal26 --dump-cpp $f.c | head -1; done
# redef_same: error: too many C macros
# undef_def:  error: too many C macros
# distinct:   (preprocesses fine)
```

A guarded header included twice (20000 macros) is fine, so the guard works. Only
redefinition leaks.

## Real-world trigger

ESP-IDF v6.0.1, esp32c3, all 81 IDF -I dirs plus the toolchain's
`lib/gcc/.../include`, `include-fixed` and `riscv32-esp-elf/include`. Each header
was tried alone as `#include "<full path>"` with `--target=riscv32 --platform=esp
--dump-cpp`, over the whole esp_wifi.h include chain (gcc -H order). The deepest
header that overflows:

`components/freertos/FreeRTOS-Kernel/portable/riscv/include/freertos/portmacro.h`

Every one of its children (spinlock.h, esp_cpu.h, soc_caps.h, csr.h, rv_utils.h,
interrupt_reg.h, esp_attr.h, esp_intr_alloc.h, ...) preprocesses fine on its own.
gcc counts 3576 macros for it. Above it, FreeRTOS.h, portable.h,
idf_additions.h, esp_event.h and esp_wifi.h all overflow too.

## Expected

Redefinition replaces the existing entry (and an identical redefinition is a
no-op, per C99 6.10.3p2). #undef frees or marks the slot so the next #define of
the same name reuses it. Converting MAX_CPREP_MACROS to a dynamic table
(unfinished/feature-dynamic-compiler-tables.md) would hide this, not fix it.

## Acceptance

redef_same.c and undef_def.c preprocess. Then portmacro.h and esp_wifi.h stop
reporting "too many C macros", and whatever comes next gets its own census
ticket. The census script is at
`~/museum_landkaart/async/tools/idf_census.sh`.
