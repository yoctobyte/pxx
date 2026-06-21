# ESP32: Compiler-Directed ISR and IRAM Support

- **Type:** feature
- **Status:** backlog (`iram;` done 2026-06-18; `interrupt;` raw-vector deferred)
- **Owner:** —
- **Opened:** 2026-06-14 (from ESP32 ISR analysis)

## Status 2026-06-18 — `iram;` DONE (both ISAs)

`procedure foo; iram;` places the routine's machine code in a new ELF
`.iram1.text` section (the IDF linker script routes it to internal IRAM).
Validated: `readelf -S` shows `.iram1.text` PROGBITS / `AX` (ALLOC|EXECINSTR)
on esp32s3 (xtensa) + esp32c3 (riscv32); `test_esp_iram` runs under qemu ==
x86-64 oracle (S/ABC/ABCDE/E). `make test` + cross-bootstrap byte-identical.

Design (single Code[] buffer, low-risk): `.text` = the full Code[] verbatim
(each iram proc keeps a dead twin there so flash PC-relative call offsets
computed at emit time stay valid); `.iram1.text` = a live duplicate of each
iram proc's contiguous byte-range (internal relative branches + xtensa l32r
literal pools survive because the whole proc moves as a unit). Cross-section
calls (flash↔iram) can't stay PC-relative, so `EmitCallProc` lowers them to an
indirect literal-slot call (same shape as an external call) recorded as an
`IramCallFix` and relocated `R_*_32` against the callee proc's own local
symbol. The extended writer (`writeELF32RelIram`, gated on any iram proc so the
proven non-iram path is byte-identical) partitions relocations by which text
section their CodePos lands in and emits proc symbols with `st_shndx` =
`.iram1.text` for iram procs. On non-ESP targets `iram;` is an accepted no-op
(same source builds as the x86-64 oracle).

## Status 2026-06-21 — `interrupt;` DONE on riscv32 (esp32c3); structurally verified

`procedure foo; interrupt;` now compiles a raw hardware trap handler on riscv32
(9ab4304). Prologue saves the interrupted caller-saved context (t0-t6, a0-a7;
ra/s0 via the normal frame, 64-byte save area above the frame), the body runs,
the epilogue restores that context and returns via `mret` (added `rv32_mret`).
`interrupt` implies `iram`, so the handler lands in `.iram1.text` (existing
placement + cross-section call lowering). Gated on `ProcIsInterrupt` →
non-interrupt riscv codegen byte-identical, self-host unchanged.

Verified structurally (`test/test_esp_interrupt.pas` + `--emit-obj`,
`riscv32-esp-elf-{readelf,objdump}`): `MyIsr` sits in `.iram1.text`; the disasm
shows the full t0-t6/a0-a7 save, the normal ra/s0 frame, a working cross-section
indirect call into flash (`esp_rom_printf`), the mirrored restore, and `mret`.

**Remaining:**
- **Live trap validation.** Installing the handler in `mtvec` + triggering a real
  trap isn't expressible in PXX yet — the rv32 inline-asm dialect has no CSR ops
  (`csrw mtvec`, `csrrs mstatus`) and `@isr`/`ProcAddrFix` (below) still errors, so
  nothing in PXX can point the vector at the handler. Options: add CSR ops +
  `mret`/`wfi` to `asmtext_rv32.inc` for a self-contained bare trap test; or fix
  `ProcAddrFix` so the handler address can be handed to a setup routine; or run on
  real esp32c3 hardware. (This is the "not qemu-validatable without a vector
  table" the deferral noted.)
- **xtensa `interrupt;`** still errors — windowed-exception ISRs need EPC/EPS +
  `rfi`/`rfe` + the windowed register spill, materially more involved than riscv.
- **`@isr` proc-address fixups** in the `.o` (`ProcAddrFix`, for `esp_intr_alloc`
  IDF-registered ISRs) still error — separate follow-up; also unblocks live
  validation above.

## Motivation

To support safe execution of Interrupt Service Routines (ISRs) under both bare-metal (`esp32-bare`) and SDK-hosted (`esp32-idf`) profiles. Code executing in an interrupt context must reside in internal Instruction RAM (IRAM) to prevent cache fetch exceptions when the flash cache is disabled. The compiler needs language-level keywords to route specific procedure code to IRAM and wrap raw bare-metal hardware interrupt registers.

## Scope

- **Language Directives:**
  - `iram;`: Compiles the procedure normally (matching the target's default ABI calling convention) but places its machine instructions in the `.iram1.text` section. Suitable for ESP-IDF registered ISRs and helper functions.
  - `interrupt;`: Compiles the procedure as a raw hardware interrupt vector handler. Emits an assembly prologue/epilogue to save and restore all CPU registers, returns via the target's hardware interrupt return instruction (e.g., `mret` on RISC-V), and places the code in the `.iram1.text` section. Suitable for bare-metal vector tables.
- **Pascal Standards Alignment:**
  - Free Pascal (FPC) and Delphi define the `interrupt;` directive to denote a hardware interrupt routine that handles its own register saving/restoring and interrupt return sequence. We adopt this standard behavior.
  - We introduce `iram;` as a custom compiler attribute/directive to designate RAM-resident functions without modifying the standard calling conventions.
- **Calling Conventions:**
  - For procedures decorated with `iram;`, the compiler automatically matches the active target's standard C calling convention (e.g., RISC-V 32-bit `ilp32` / `cdecl` or Xtensa `windowed`/`call0` ABI as configured by target flags). The programmer does not need to specify manual calling conventions in the procedure signature.
- **ELF Relocatable Object Writer:**
  - Update `writeELF32Rel` in [elfwriter.inc](file:///home/rene/frankonpiler/compiler/elfwriter.inc) to define and output the `.iram1.text` section.
  - Partition the compiler's unified `Code` buffer by section, adjusting internal symbol offsets and relocation targets dynamically.

## Non-goals

- Enforcing FreeRTOS/ISR-safe API calling limits at compile time.
- Generating automated vector table routing from the compiler (handled by developer code or SDK APIs).

## Acceptance

- Compiler accepts procedure declarations with the new directives:
  ```pascal
  procedure my_gpio_isr(arg: pointer); cdecl; iram;
  procedure my_raw_hw_isr; interrupt;
  ```
- Executing `./pascal26 --target=riscv32 --emit-obj` produces an ELF object containing both `.text` (Flash) and `.iram1.text` (IRAM) sections.
- `readelf -S` verified correct section headers, flags (`SHF_ALLOC | SHF_EXECINSTR`), and offsets.
- Linking with ESP-IDF puts `.iram1.text` in IRAM, and the application runs safely in cache-disable states.
