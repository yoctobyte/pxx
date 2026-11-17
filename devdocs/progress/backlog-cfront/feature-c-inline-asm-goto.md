---
slug: feature-c-inline-asm-goto
track: C
prio: 30
type: feature
status: backlog
created: 2026-11-17
found-by: pxx2, rump repro g14c (`asm goto("testl %0,%0; jz %l1" :: "r"(x) :: zero)`)
tags: [cfront, inline-asm, x86-64, rump]
blocked-by: []
summary: "asm goto is refused ('the jump out of the template would have no target'). The template is encoded to bytes at PARSE time, but a C label's code address is known only at codegen, so a jump to %lN needs a fixup from the asm span to the label. The likely shape is to record (span offset, label) pairs on the AN_ASM node and patch rel32 when the label is placed, the way C goto resolves. Linux/NetBSD use it for static keys and for jump labels in atomics. The last item of g14c."
---

# asm goto

Everything else in rump repro g14c compiles as of feature-c-inline-asm-rump-x86-operand-forms. This is the one remaining item.
