# Relocatable ELF32 object writer (.o for ESP-IDF linking)

- **Type:** feature
- **Status:** done
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

## Log
- 2026-06-12 — DONE (commit d30bcae). `writeELF32Rel` in compiler/elfwriter.inc;
  `--emit-obj` flag or inferred from a `.o` output name. Acceptance held:
  readelf clean on both targets; links against a C `main` shim with
  xtensa-esp32s3-elf-gcc and riscv32-esp-elf-gcc (ESP-IDF toolchains under
  ~/.espressif); objdump spot-check confirms relocated literals hit the right
  .bss addresses (riscv32 0x123b8 = .bss+0x1050, xtensa 0x4022c8 likewise).
  Externals: undefined GLOBAL symbols + indirect call via relocated literal
  slot (l32r+callx0 / lw+jalr, new xtensa_callx0 encoder); also delivers the
  stage-1 "ELF symbol tables" leftover (every proc = LOCAL FUNC symbol, entry
  exported GLOBAL as app_main). Regression test: `make test-emit-obj`
  (test/test_emit_obj.pas); host suite + i386/aarch64/arm32 oracles green;
  FPC-built and self-hosted compilers emit byte-identical .o files.
  Landmines hit: (1) self-hosted backend miscompiles ~7+-parameter calls —
  filed bug-many-param-call-corruption, worked around with two <=6-param
  shdr helpers; (2) self-host file path needs explicit sysfchmod (sysopen
  O_CREAT leaves mode 000). Note for feature-esp32-idf-riscv32: app_main
  currently never returns (bare-metal terminal self-loop) — the idf profile
  needs a returning runtime epilogue.
