---
prio: 60  # auto
---

# Inline asm blocks on xtensa (last leg of the multi-arch rollout)

- **Type:** feature — Track A
- **Status:** done
- **Owner:** claude-acpn
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

## Done 2026-08-16

All three engine gaps closed, and none of them needed a new mechanism.

1. **Relocations.** The engine now takes `la <reg>, @fp|@glob|@data` plus an
   offset hole and calls the BACKEND's `EmitFrameAddrXtensa` /
   `EmitLoadGlobAddrXtensa` / `EmitLoadDataRefXtensa` — the L32R literal-pool
   sugar the header listed as deferred already existed inside
   ir_codegen_xtensa.inc, so the fix was to reach it (two forwards in
   symtab.inc) rather than to write it again.
2. **Locals as an operand.** Confirmed impossible as the ticket says, so it is
   a DIAGNOSTIC, not a silent wrong offset: a variable is legal only as the
   memory operand of a load/store (`l32i a4, n`, which lowers to "address into
   a8, access at offset 0") or after `la`. Anywhere else the error names both
   legal spellings. a8 is refused as the value register of such an access,
   where a store would overwrite its own address.
3. **Frame pointer.** Never spelled in the engine at all — `EmitFrameAddrXtensa`
   is what knows it is a7 under windowed and a15 under Call0, and what falls
   back to the literal pool past ADDI's ±128. Calling it instead of copying it
   is what made gap 3 disappear along with gap 1.

Also folded the eight load/store arms into one table (`AsmXtensaIsLoadStore` /
`AsmXtensaEmitLoadStore`) that both the plain and the variable-operand path
call, and split `EmitAsmXtensa` into the BlockBegin/ProcessLine/BlockResolve
shape its five siblings already had, so the inline replay shares their label
and forward-branch bookkeeping.

**Acceptance:** `test/test_esp_bare_asm.pas` — params, a local, labels with a
backward jump and a conditional branch (xtensa has no zero register, so the
loop sentinel is materialized), a global via `la`, a global as a direct load
operand, and a 1KB frame that forces the literal-pool address. Boots on
esp32s3 under Espressif qemu; UART output matches the x86-64 oracle byte for
byte (42/55/42/43/263). The windowed ABI is checked to lower. Wired into the
esp-bare make target.
- 2026-08-16 — resolved, commit d3eaa189e.
