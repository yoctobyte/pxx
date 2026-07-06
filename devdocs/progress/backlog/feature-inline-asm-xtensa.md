---
prio: 60  # auto
---

# Inline asm blocks on xtensa (last leg of the multi-arch rollout)

- **Type:** feature — Track A
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-03
- **Relation:** Split out of [[feature-inline-asm-multi-arch]] when that ticket
  landed its riscv32/aarch64/arm32/i386 legs (2026-07-03). Deliberately low
  priority per user direction (Espressif path prefers riscv32; xtensa last).

## Goal

Wire Pascal `asm ... end` blocks to `EmitAsmXtensa` (asmtext_xtensa.inc) the
same way the other five targets work: parse-time text capture in asmenc.inc
(`AsmParseBodyText<T>`), codegen-time replay via a
BlockBegin/ProcessLine/BlockResolve engine API, IR_ASM case in
ir_codegen_xtensa.inc.

## Why it did not ship with the other legs — engine gaps first

The capture/replay pattern is mechanical, but asmtext_xtensa.inc is missing
the pieces the pattern leans on (all other engines had them already):

1. **No relocation forms.** No `@glob`/`@data` handling → no global-variable
   access idiom. Needs an L32R-literal-pool (or movi+add) reloc form calling
   EmitGlobRef/EmitDataRef — this is the "L32R literal-pool sugar" already on
   the engine's own deferred list (see asmtext_xtensa.inc header and
   feature-xtensa-asm-emitter's notes).
2. **Locals can't be a direct operand.** `l32i/s32i` offsets encode as
   UNSIGNED imm8*4 (0..1020; negative values silently wrap — see
   xtensaenc.inc xtensa_l32i), but frame offsets are negative
   (fp-relative), so a `<off>(fp)`-style substitution is impossible. The
   backend itself always materializes the address first
   (EmitFrameAddrXtensa → addi ±128 or movi+add into a8). Inline-asm var
   substitution therefore needs a multi-line rewrite through a documented
   scratch register (a8/a9 are the backend's address/scratch temps), or an
   engine pseudo-op (`lvar at, <off>` etc.).
3. **Frame pointer is ABI-dependent:** a15 under call0, a7 under windowed
   (EmitFrameAddrXtensa). XtensaABI is known at parse time, so capture can
   pick — just don't hardcode a15.

## Acceptance

Same shape as test_asm_rv32/a64/arm32/386.pas (42/55/42 oracle), run under
tools/esp_run_bare.sh or qemu xtensa; wire into make test-esp-bare or a
dedicated target.

## Log
- 2026-07-03 — Filed on split from [[feature-inline-asm-multi-arch]].
