# i386 text-assembler (`EmitAsm386`) for cleaner x86-32 codegen

- **Type:** feature
- **Status:** done
- **Owner:** Antigravity
- **Depends-on:** feature-array-of-const (DONE), feature-asm-text-emitter
  (x86-64 core + shared `asmtext.inc` helpers, DONE)
- **Opened:** 2026-06-14

## Motivation

`ir_codegen386.inc` is **2947 lines**, ~970 of them raw `EmitB($..)` with the
mnemonic only in a trailing comment, plus **57 manual `CodeLen`/`Patch32` jump
sites**. Unreadable and the exact shape that produced the `19 DB` vs `19 D3`
ModRM bug — a class of bug the encode-ModRM-once text assembler cannot make.
This is the highest-leverage conversion: biggest file, hottest backend, and it
feeds the i386 self-host arc (current wall: `Expected: unit` miscompile —
[[project_i386_selfhost_arc]]).

## Why first / cheapest

`EmitAsm386` shares the x86 ModRM/SIB core **already written** for `EmitAsmX64`
in `compiler/asmtext.inc`. i386 is the same encoder with REX dropped and the
register set narrowed to `eax..edi`/`esp`/`ebp` (no `r8..r15`, no RIP-relative).
Mostly a 32-bit entry point over the existing x86 layer, not new ISA work.

## Scope (incremental — mix freely with `EmitB`)

1. `EmitAsm386(const items: array of const)` + single-line overload, over the
   shared x86 core. Registers 8/16/32-bit (`al/ax/eax` …), `[base±disp]`,
   immediates; markers `%` (width inferred), `@data`/`@glob` (via `EmitDataRef`/
   `EmitGlobRef`), `.label:` with rel8/rel32 back+forward resolution — the
   mechanism that deletes the 57 manual jump sites.
2. Grow the mnemonic table on demand — start with exactly what the converted
   blocks use (`mov push pop add sub and or xor cmp lea inc dec` + `jmp`/`jcc`
   + `int 0x80`/`ret`/`leave`).
3. **Convert `EmitwriteUInt64_386`** (fixed body + a backward-jump loop + two
   `@data`) and at least one **bound** site (the `IR_LOAD_SYM` `[ebp+disp]`
   path). Leave heavily-dynamic blocks on `EmitB`/typed encoders.

## Landmines

- **Byte-identity discipline:** converting a block shifts the emitted compiler's
  bytes, fine *as long as* the i386 fixedpoint `cmp` stays clean (native↔self
  both run the new assembler). Re-run after each conversion batch.
- **PXX self-host:** no short-circuit `and`/`or` + EMPTY-AnsiString index = nil
  deref → route conditional char reads through `AsmTextCharAt`; never reassign a
  `var AnsiString` param; keep scratch label tables module-global. (Already paid
  for in `asmtext.inc`; reuse those helpers, don't re-hit.)
  [[project_pxx_and_not_shortcircuit]] / [[project_pxx_array_of_const_selfhost]].

## Acceptance

- `EmitAsm386` with the marker/label/binding rules + single-line overload.
- `EmitwriteUInt64_386` and ≥1 bound site converted; output correct.
- `make test` + `make test-i386` green; **i386 self-fixedpoint byte-identical**.
- A focused `test/test_asm_emit_386.pas` against known-good bytes
  (imm/disp/label/reloc).

## Deferred

Full `ir_codegen386.inc` conversion (incremental, on demand); retargeting the
user `asm … end` path (`asmenc.inc`) onto the shared engine (own follow-up).

## Log

- 2026-06-14 — opened. Mirrors the `EmitAsmX64`/`EmitAsmXtensa` work; first of
  the three remaining target emitters (386 → aarch64 → arm32). Shares the x86
  core in `asmtext.inc`; primary payoff is the 970-`EmitB`/57-jump cleanup and
  the i386 self-host arc.
- 2026-06-14 — Claimed by Antigravity.
- 2026-06-14 — Completed. `EmitAsm386` implemented, `EmitwriteUInt64_386` and bound local/param loads converted. Verified via standalone test `test/test_asm_emit_386.pas` and compiler bootstrap. Commit: c8da1613a2df2cfbf4aa4e88cab33012bbc751d2.
