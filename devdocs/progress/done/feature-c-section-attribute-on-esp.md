---
track: C
tags: [C, esp, xtensa, riscv32, freestanding, attribute, gibux]
prio: 30
type: feature
blocked-by: []
summary: "__attribute__((section(\"x\"))) is honoured in a freestanding ESP object (--freestanding --emit-obj, xtensa and riscv32). A function in .iram* goes to .iram1.text with its inline literals, and every call into, out of or between IRAM bodies goes through a relocated literal. A global of any name gets an ELF section of exactly that name, for example .rodata_desc for the IDF app descriptor. Elsewhere the attribute stays ignored."
status: done
owner: unassigned
---

# __attribute__((section)) on ESP

Item 3 of Gibux's ESP32-S3 port.

## Functions
- A function whose section name starts with `.iram` becomes `ProcIram`. That covers both `.iram1.text` and IDF's IRAM_ATTR spelling `".iram1" "." "N"`, whose pieces are concatenated. Its body and its L32R literal pool are emitted together in `.iram1.text`. The tests confirm that no relocation in `.rela.iram1.text` reaches a literal outside that section.
- Any other section name on a function prints a warning, and the function stays in `.text`.

## Globals
- A global with any section name gets its own section of exactly that name, with the variable's bytes and a symbol in that section. The section is SHF_ALLOC, plus SHF_WRITE unless the name starts with `.rodata` or the variable is const. It is emitted whether or not anything references it, as gcc does with `used`.
- References to the variable relocate against its own section.
- The bytes keep a dead twin in .data/.rodata, so no Data[] offset moves.

## Fixes made along the way
- **IramCallFix gate (symtab.inc):** it now also covers EspFreestandingObj. Before, flash↔IRAM calls in a freestanding object were direct calls, which are wrong once the linker splits the sections.
- **IRAM→IRAM calls:** these now go through a literal too. The writer packs the IRAM bodies, so the Code[] distance between two of them is wrong whenever a flash routine sat in between. This was latent in the IDF Pascal `iram;` path as well.

## Limits
- A pointer (an address relocation) inside a named data section is refused.
- The twin costs RAM for a writable named variable: 2x its size, which is bad for a big `.noinit` buffer.
- `.bss`-style NOBITS named sections are not supported. Every named section is PROGBITS.

## Tests
- Source: test/c_esp_section_attr.c.
- Checker: tools/check_esp_section_attr.py. It covers esp32s3 and esp32c3, and links with an esp32s3.ld-shaped script using KEEP(.rodata_desc).
