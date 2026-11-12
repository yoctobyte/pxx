---
track: core
prio: 40
type: bug
blocked-by: []
summary: "On the i386 text assembler (EmitAsm386 and the i386 inline-asm replay), a `[base+index*scale]` operand set the shared encoder's EncMemIndex and nothing cleared it, so the NEXT memory operand encoded through EncModRMMem picked up the stale index: `movzx edx, byte [ecx+edx]` then `mov ecx, [ebp+8]` produced `mov ecx, [ebp+edx+8]`. Fixed by resetting EncMemIndex before and after every i386 line, as EmitAsmX64 already did."
status: done
owner: unassigned
---

# An indexed i386 asm operand leaks its index into the next memory operand

## Found

2026-11-12, while converting raw i386 byte runs to EmitAsm386 text. A
harness ran every candidate line through the shipped parser and encoder.
Lines that followed an indexed operand came out with a SIB byte they never
asked for (`8B 4C 0D 08` for `mov ecx, [ebp+8]`, expected `8B 4D 08`).

## Cause

AsmTextOperand (asmtext.inc) records an index register in the x64enc global
EncMemIndex, and EncModRMMem consumes it. On x86-64 the reset happens per line
in AsmTextLineMemo. The i386 path calls AsmTextLine386 directly and never
reset it, so the index stayed set for the next memory operand. That operand
could be in the next asm line or in any later raw encoder call.

test/test_asm_emit_386.pas could not see this, because it carried its own
mock copies of AsmTextOperand and EncModRMMem. The mock had no index support
at all. It now includes the real asmregs.inc, x64enc.inc and asmtext.inc, the
same environment as test_asm_emit_x64.pas.

## Fix

- AsmTextLine386 sets EncMemIndex := -1 on entry.
- Asm386ProcessLineEx resets it after each ordinary instruction.

## Checked

test_asm_emit_386 has two new rows: an indexed line followed by a plain
`[ebp+8]` load, once within one call and once across two calls. Both fail
without the fix (the stale SIB byte) and pass with it. The bytes come from
GNU as --32.
