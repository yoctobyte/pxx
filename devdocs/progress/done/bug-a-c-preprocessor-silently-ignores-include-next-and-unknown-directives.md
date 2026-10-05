---
track: A
prio: 50
type: bug
blocked-by: []
summary: "The C preprocessor has no #include_next and silently ignores it, along with any unknown directive (`#bogus_directive` compiles without a word). GCC's wrapper <stdint.h> (first on any toolchain include path) does `# include_next <stdint.h>`, so newlib's stdint never arrives: no uint8_t/uint32_t typedefs exist, and every struct member using them disappears (see the sibling ticket on unknown type names). In ESP-IDF that empties esp_ip_addr_t, so `uses esp_netif` fails with \"no member named 'type'\". Measured 2026-10-05, frank-user master 8be43bcb06."
status: done
owner: ""
---

# C preprocessor silently ignores #include_next (and every unknown directive)

- **Type:** bug (C preprocessor) — **Track A**. Silent wrong output, so prio 50.
- **Filed:** 2026-10-05 from `~/museum_landkaart`, the ESP-IDF header-import census.

## Repro

```sh
mkdir -p a b
printf '#include_next <foo.h>\n' > a/foo.h
printf 'typedef unsigned int my_t;\n#define FOO_B 1\n' > b/foo.h
printf '#include <foo.h>\nint main(void){ my_t x = FOO_B; return (int)x; }\n' > m.c
pascal26 -Ia -Ib --dump-cpp m.c     # nothing from b/foo.h appears
pascal26 -Ia -Ib m.c m              # fails later, far from the cause
printf '#bogus_directive\nint main(void){return 0;}\n' > z.c
pascal26 z.c z                      # compiles, no diagnostic
```

## Real-world chain

ESP toolchain include order (as gcc uses it): `lib/gcc/riscv32-esp-elf/15.2.0/include`,
`include-fixed`, `riscv32-esp-elf/include` (newlib). gcc's `include/stdint.h` is
`#if __STDC_HOSTED__ / # include_next <stdint.h>` (pxx predefines __STDC_HOSTED__=1,
cpreproc.inc:3658). The include_next is dropped, so the preprocessed esp_netif.h has
no `uint8_t`/`uint32_t` typedef anywhere. `struct esp_ip4_addr { uint32_t addr; }`
and `uint8_t type;` silently lose their members, and the first access
(`esp_netif_ip_addr_copy` in esp_netif_ip_addr.h:157) reports `no member named 'type'`.

Workaround that proves it: put newlib's dir before gcc's (`CENSUS_NEWLIB_FIRST=1
tools/idf_census.sh esp_netif` in ~/museum_landkaart/async, together with the
predefines ticket's prefix). Then `uses esp_netif` compiles.

## Expected

- `#include_next <x>` / `"x"`: continue the search after the directory that held
  the current file (the GCC extension that every libc wrapper relies on).
- An unknown directive in an active branch is an error, as in GCC ("invalid
  preprocessing directive #bogus_directive"). `#error` already reports now, so the
  docs/targets/c-frontend.md note saying #error is "silently ignored" is stale too.

## Acceptance

The repro's dump contains `typedef unsigned int my_t;`, z.c fails with a
directive diagnostic, and esp_netif imports with gcc's include order.
