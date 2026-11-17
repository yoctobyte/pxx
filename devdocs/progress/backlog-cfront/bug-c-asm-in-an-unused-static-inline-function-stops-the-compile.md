---
slug: bug-c-asm-in-an-unused-static-inline-function-stops-the-compile
track: C
prio: 50
type: bug
status: backlog
created: 2026-11-16
found-by: pxx (Gibux seat), rump-pxx g20 (x86 invpcid) and the same shape on --target=xtensa
tags: [cfront, inline-asm]
blocked-by: []
summary: "A `static inline` function that is never called still has its inline asm assembled, so an instruction pxx's assembler lacks (invpcid) or any x86 asm on Xtensa (\"inasm with a non-empty template is only supported on x86-64, i386 and aarch64\") stops the compile. gcc never emits an unused static inline. Defer asm assembly to emission, or skip unused static inline bodies."
---

## 2026-11-17: the xtensa half is done

feature-c-xtensa-inline-asm-templates: xtensa encodes C templates at codegen
and asks `AsmXtensaLineKnown` at parse time, so an unknown instruction in an
unused static inline poisons the routine instead of stopping the compile. The
x86 half (invpcid in rump-pxx g20) is still open: x86 encodes at parse time.
