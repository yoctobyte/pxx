# Relocatable ELF32 object writer (.o for ESP-IDF linking)

- **Type:** feature
- **Status:** working
- **Owner:** claude
- **Unblocks:** feature-esp32-idf-riscv32, feature-esp32-idf-xtensa
- **Opened:** 2026-06-12 (esp32-idf integration plan; follow-on to feature-target-esp32)

## Motivation

The esp32-idf profile works by emitting a relocatable `.o` that ESP-IDF's
build registers as a prebuilt component and links with `xtensa-esp-elf-ld` /
`riscv32-esp-elf-ld`. IDF then owns boot, FreeRTOS init, and every vendor API;
PXX provides `app_main`. The compiler currently emits only fully-linked
ET_EXEC images with absolute patches (`writeELF32`).

Key simplification earned by stage 1 (see done/feature-target-esp32): both
32-bit ESP backends route **every absolute address through a 32-bit literal
slot** (Xtensa jump-over-literal islands, RISC-V auipc pools), and
intra-object calls are resolved at emit time. So relocations collapse to
plain `R_XTENSA_32` / `R_RISCV_32` data-word relocs on literal slots — no
code relocations, no `R_XTENSA_SLOT0_OP`, no linker-relaxation interaction.

## Scope

- New `--emit-obj` output mode (or inferred from `.o` output name) producing
  ET_REL ELF32 with section headers: `.text`, `.data`, `.bss`, `.symtab`,
  `.strtab`, `.rela.text` (+ `.rela.data` for data→data pointers if needed).
- Map existing fixup tables 1:1 to relocations:
  - `Fixups` (data refs) → `R_*_32` against a `.data` section symbol,
  - `GlobFix` (BSS refs) → `R_*_32` against a `.bss` section symbol,
  - `DataPtrFix` → `.rela.data` entries.
- Symbol table: emit every proc as a global function symbol (this also
  delivers the "ELF symbol tables for debugging" acceptance left over from
  stage 1). Program entry exported as `app_main` for the idf profile.
- **External imports:** `external` procedure decls become undefined symbols.
  Call path loads the address from a relocated literal slot and calls
  indirectly (`l32r` + `callx0` on Xtensa, `lw` + `jalr` on RISC-V) — keeps
  the zero-code-reloc property.
- Per-symbol literal-slot dedup is optional; one slot per call site is fine
  for v1.

## Non-goals

- No archive (.a) writer — a single .o per program is enough for a component.
- No DWARF. Symbols only.
- No section GC support (`-ffunction-sections` style); one `.text` blob.

## Acceptance

- `readelf -a` clean on emitted `.o` for both targets (sections, symbols,
  relocs all sane).
- Xtensa `.o` links against a trivial C `main` shim with
  `xtensa-esp32s3-elf-gcc` (toolchain installed at `~/.espressif/tools/...`,
  PATH via `. ~/esp/esp-idf/export.sh`); linked image's relocated literals
  point at the right data/bss addresses (objdump spot-check).
- RISC-V `.o` links with `ld.lld` or riscv32-esp-elf-ld once the C3 toolchain
  is installed (`~/esp/esp-idf/install.sh esp32c3`).
- Host suite (`make test`, cross oracles) untouched — ET_EXEC path unchanged.

## Notes

- ELF32 shdr/sym/rela struct layouts are small; follow `writeELF32` style in
  `compiler/elfwriter.inc`.
- Self-hosted compiler has no execve — validation via external tools happens
  in Makefile/test scripts, never from inside the compiler.
