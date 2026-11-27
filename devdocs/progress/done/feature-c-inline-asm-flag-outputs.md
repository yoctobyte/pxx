---
title: "C inline asm: x86 flag outputs (\"=@ccCOND\") and bt/bts/btr/btc"
status: done
owner: claude-dupwt
prio: 65
area: cfront
---

gcc 6+ lets an x86 asm output be a condition flag: `"=@cce" (res)` gives res
1 when ZF is set after the template. FreeBSD's atomic_cmpset and
atomic_testandset use it, and drm-kmod reaches them through LinuxKPI. It was
the first error in 33 of the 2100 GPU-driver compiles in the first pxx census
(feature-nodisx-linux-gpu-drivers-built-by-pxx). testandset also needed
`btsl`, which the AT&T path did not encode, and its bit number is an "Ir"
constraint.

Fix:
- compiler/cparser.inc, CAsmParseOperandSection: `@ccCOND` (any jCC suffix,
  checked by CAsmFlagCondOk) binds the operand as a byte register (class q)
  and records COND in the new TCAsmOperand.FlagCC. CAsmBuildBlock encodes
  `setCOND %bN; movzbl %bN, %kN` after the template, before the outputs are
  stored. It is an output-only constraint, and x86 only.
- "Ir", "ri", "rn" and the like (r plus immediate letters) read as "r", the
  same reading that honours "rm" and "g".
- compiler/asmenc.inc: bt/bts/btr/btc r/m,reg (0F A3/AB/B3/BB) and r/m,imm8
  (0F BA /4../7). compiler/asmatt.inc routes them.

Test row c_asmflag26 (test/c_inline_asm_flag_outputs.c): cmpxchg with =@cce,
bts with =@ccc, cmp with =@ccb into a long, and the other bit ops in register
and immediate forms. Its expected output is gcc's.
