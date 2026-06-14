# ESP32: Compiler-Directed ISR and IRAM Support

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-14 (from ESP32 ISR analysis)

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
