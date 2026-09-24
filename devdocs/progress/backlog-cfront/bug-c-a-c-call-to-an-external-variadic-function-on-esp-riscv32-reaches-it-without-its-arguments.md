---
slug: bug-c-a-c-call-to-an-external-variadic-function-on-esp-riscv32-reaches-it-without-its-arguments
track: C
prio: 30
type: bug
blocked-by: []
summary: "A C call to a variadic function that is NOT defined in the program (an IDF/ROM external such as esp_rom_printf) runs and prints nothing on esp32c3 (riscv32, --platform=esp). Disassembly suggests the variadic arguments are marshalled into pxx's own va block (stores into .bss) rather than a0..a7 as the RISC-V ilp32 C ABI requires of a call to a foreign function. crtl's own variadics (printf) are unaffected because caller and callee both use pxx's convention; the defect is specifically the call to an external that uses the platform C ABI."
---

# A C call to an external variadic on ESP riscv32 loses its arguments

Found 2026-09-24 (frankS) while bringing up `feature-c-esp-conformance-coverage`.

## Repro (HEAD after the ESP C entry stub landed)

```c
extern int esp_rom_printf(const char *fmt, ...);
int main(void){ esp_rom_printf("ROM %d\n", 5); return 0; }
```

`tools/esp_run.sh --chip esp32c3 r.c` boots, IDF logs `Returned from
app_main()`, and **nothing** is printed. Controls in the same session, same
binary: `printf("hi %d\n", 42)` (crtl's printf) prints `hi 42`; a Pascal
`esp_rom_printf(fmt: string; v: Integer); external;` (non-variadic
declaration) prints fine in `examples/esp32/dns-c3`. So the stub, the link and
the ROM routine all work; the variadic call to a foreign definition does not.

## Measured vs inferred

- Measured: no output, on esp32c3 QEMU, with the three controls above.
- Inferred from `objdump -dr` of `main`: the arguments are stored into a block
  addressed through a `.bss` relocation before the call, the shape of pxx's own
  va marshalling, rather than being placed in a0/a1. Not traced through the
  codegen yet -- confirm before building on it.

## Scope to check

Whether the same holds on hosted targets for a C call into a `--dynlib` or
`-l` library's variadic (x86-64/aarch64 `printf` from libc when crtl is not the
provider) -- if so this is not ESP-specific and belongs in backlog-core.
xtensa cannot be checked yet: variadic C on the windowed ABI is refused.
