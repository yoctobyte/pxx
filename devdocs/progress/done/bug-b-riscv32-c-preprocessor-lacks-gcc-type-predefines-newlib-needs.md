---
track: A
prio: 45
type: bug
blocked-by: []
summary: "For --target=riscv32 the C preprocessor doesn't predefine the GCC type/size macros (__INTPTR_TYPE__, __INT32_TYPE__, __SIZEOF_*__, ...) that newlib's sys/_intsup.h uses, so the ESP toolchain's own <stdint.h> fails with '#error Unable to determine type definition of intptr_t'. Prefixing gcc's 351 predefines (riscv32-esp-elf-gcc -march=rv32imc_zicsr_zifencei -mabi=ilp32 -dM -E) makes it preprocess. Every ESP-IDF header needs newlib. Measured 2026-10-05, frank-user master 804851ea40."
status: done
owner: ""
---

# riscv32: the C preprocessor lacks the GCC type predefines newlib needs

- **Type:** bug (C preprocessor predefines per target) — **Track A**.
- **Filed:** 2026-10-05 from `~/museum_landkaart`, the ESP-IDF header-import census.

## Repro

```sh
T=~/.espressif/tools/riscv32-esp-elf/esp-15.2.0_20251204/riscv32-esp-elf
SYS="-I$T/lib/gcc/riscv32-esp-elf/15.2.0/include -I$T/lib/gcc/riscv32-esp-elf/15.2.0/include-fixed -I$T/riscv32-esp-elf/include"
printf '#include <stdint.h>\nint main(void){return 0;}\n' > s.c
pascal26 --target=riscv32 --platform=esp --dump-cpp $SYS s.c | head -1
# error: #error in .../riscv32-esp-elf/include/sys/_intsup.h: "Unable to determine type definition of intptr_t"

echo | riscv32-esp-elf-gcc -march=rv32imc_zicsr_zifencei -mabi=ilp32 -dM -E - > gcc_predefs.h   # 351 lines
printf '#include "gcc_predefs.h"\n#include <stdint.h>\nint main(void){return 0;}\n' > s2.c
pascal26 --target=riscv32 --platform=esp --dump-cpp $SYS s2.c | head -1      # preprocesses fine
```

(The esp_wifi.h chain's first `stdint.h` resolves elsewhere and passes. Newlib's
`stdint.h`, `inttypes.h` and `sys/_intsup.h` fail as soon as they're reached
directly, and IDF reaches them, for example via esp_rom_sys.h.)

## Expected

For each target, predefine what GCC predefines for that ABI, at least the
`__*_TYPE__`, `__*_MAX__`, `__SIZEOF_*__`, `__CHAR_BIT__`, `__riscv*`, `__ILP32__`
families. The gcc dump above is the oracle. Then a Pascal `uses` of a header
behaves the same, with no prefix file. That matters because a `uses` has no way
to add one.

## Acceptance

s.c preprocesses with no prefix; the same for `--target=xtensa` against
xtensa-esp-elf-gcc's own dump.
