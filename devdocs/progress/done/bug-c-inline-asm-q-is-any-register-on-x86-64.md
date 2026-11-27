---
title: "C inline asm: \"q\" was limited to a b c d on x86-64"
status: done
owner: claude-dupwt
prio: 70
area: cfront
---

On x86-64 every general register has a byte form (sil, dil, r8b...), so gcc's
"q" is the same set as "r". Only i386 limits it to a, b, c and d. pxx used the
i386 rule everywhere. ck_pr.h's ck_pr_cas_64_2 (cmpxchg16b) takes b and c as
operands and clobbers rax and rdx, so its "=q" and "q" found no register: 601
GPU-driver compiles in the fourth census
(feature-nodisx-linux-gpu-drivers-built-by-pxx).

Fix (compiler/cparser.inc, CAsmParseOperandSection): on x86-64, "q" reads as
"r". "Q" (the %h high byte) is still a, b, c or d everywhere. Test row
c_paintq26, a cmpxchg with b and c taken and rdx clobbered.
