---
track: A
prio: 50
type: bug
blocked-by: []
summary: "x86-64 encoder (x64enc.inc), found 2026-11-11 while moving raw EmitB code to EmitAsmX64: (1) mov/lea/push/pop/inc/dec/movzx/movsx with a memory operand used the reg-reg REX rule, so a BASE of rsp..rdi on a byte op forced a spurious REX 40 (`mov [rdi], cl` = 40 88 0F, not 88 0F), and an INDEX register r8..r15 lost REX.X; (2) and/or/add/sub/xor/cmp/adc/sbb on al/ax/eax/rax never used the accumulator form (04/05 + 8*ext), a byte longer than GNU as; (3) SSE scalar ops had no absolute-memory form, so `movsd [@glob], xmm0` was an assemble error; (4) push/pop took no memory operand (`push [rax+%]` on the C path); (5) the x64 harness resolved registers with a mock table lacking r8d..r15d. All fixed; tools/x64_asm_static_check.py now assembles every literal EmitAsmX64 line in gate quick."
status: done
owner: unassigned
---

# x86-64 encoder: spurious REX on byte memory ops, missing accumulator forms, no SSE [@glob]

Found while converting raw `EmitB($..)` x86-64 codegen to the text assembler
(`refactor-x86-64-raw-emitb-to-the-text-assembler.md`, batch 21). The batch's
disassembly oracle flagged 130 instructions changed across 14 corpus programs,
every one `mov BYTE PTR [rdi],cl` gaining a `rex` prefix.

## 1. Memory forms used the register-register REX rule

`x64_mov_reg_mem`, `x64_mov_mem_reg`, `x64_lea_reg_mem`, `x64_push_mem`,
`x64_pop_mem`, `x64_inc_mem`, `x64_dec_mem` and `x64_movx_reg_mem` called
`EncPrefixAndREX(size, reg, baseReg, ..)`. That helper's byte-size rule ("spl,
bpl, sil, dil need a REX") looks at the rm field, which for a memory operand is
the BASE register, not a byte register. So `mov [rdi], cl` came out
`40 88 0F`. It meant the same but was one byte longer. The helper also ignores
`EncMemIndex`, so `[base+r9*8]` through these forms would have lost REX.X and
addressed `rcx*8` instead. That was wrong code, but no caller had used the
form yet. All eight forms now call `EncPrefixAndREXMem`, the memory twin. It
reads the index and applies the byte rule to the register operand only.

## 2. No accumulator short forms

`EncALUImm` always emitted `80 /ext ib` or `81 /ext imm32`. With al/ax/eax/rax,
the ModRM-less forms `04+8*ext ib` and `05+8*ext imm32` are one byte shorter.
GNU as uses them. On one -O1 nilpy program, 225 `and rax, imm32` and 26 more
add/sub/xor went from 6 to 7 bytes, compared with the raw bytes they replaced.
The assembler now picks the accumulator form when the value needs 32 bits, or
the operand is al. For an 8-bit value on a wider register, `83 /ext ib` is
still shorter, and it is kept.

## 3. SSE scalar <-> absolute memory

The SSE path accepted only `xmm, xmm` and `[base+disp]`. `movsd [@glob], xmm0`
(and `[@data]`, `[num]`) was an assemble error. That made 175 of 472 corpus
programs fail to compile once symtab.inc's global float stores were converted.
`AsmEncSseAbs` emits prefix, REX.R if needed, `0F op`, then the absolute
ModRM/SIB form that `AsmEncAbsRM` already used for GP registers.

## 4. push / pop had no memory operand

`push [rax+%]` (FF /6) is on the C aggregate-argument path. GNU as accepted it,
so the converter accepted it. Our assembler took only a register and stopped
with "push expects a register" while compiling lib/crtl/src/stdio.c. The
corpus check never saw this, because the corpus compiled no C. test-nilpy's
cpyext, cproc and dotted-package rows (9 FAIL) caught it. push and pop now take
`[mem]` through the encoder's x64_push_mem/x64_pop_mem, and the absolute forms
through AsmEncAbsRM.

## 5. The harness tested a mock register table, not the real one

test/test_asm_emit_x64.pas (and _386) resolved register names with a
hand-written table that had no r8d..r15d. So `xor r8d, r8d`, used in the
compiler since raw-asm batch 1, had never been assembled by a harness. The
real resolver now lives in compiler/asmregs.inc, split out of asmenc.inc, and
both harnesses include it.

## The guard: tools/x64_asm_static_check.py (gate.sh quick)

This tool assembles every literal EmitAsmX64 line in the compiler source
through the real assembler, with dummy hole values. That is 806 distinct
lines. It runs whether or not a corpus reaches the line. On the source from
before this fix it reports exactly the two push lines and the r8d/r9d lines.
After the fix it reports 0.

## Tests

`test/test_asm_emit_x64.pas` has new cases with bytes taken from GNU as:
- byte stores and loads with a low-register base;
- `[rdi+r9*8]` through mov and lea;
- `inc byte [rdi]`;
- the accumulator forms, including the rcx control (keeps `81`) and the imm8
  control (keeps `83`);
- SSE `[@glob]` loads and stores, including xmm9 (REX.R after the F3 prefix).

Two old expectations pinned the longer form, with a note that GNU as picks the
shorter one. They now expect the GNU as bytes.
