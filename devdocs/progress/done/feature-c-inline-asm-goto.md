---
slug: feature-c-inline-asm-goto
track: C
prio: 30
type: feature
status: done
created: 2026-11-17
found-by: pxx2, rump repro g14c (`asm goto("testl %0,%0; jz %l1" :: "r"(x) :: zero)`)
tags: [cfront, inline-asm, x86-64, rump]
blocked-by: []
summary: "asm goto is refused ('the jump out of the template would have no target'). The template is encoded to bytes at PARSE time, but a C label's code address is known only at codegen, so a jump to %lN needs a fixup from the asm span to the label. The likely shape is to record (span offset, label) pairs on the AN_ASM node and patch rel32 when the label is placed, the way C goto resolves. Linux/NetBSD use it for static keys and for jump labels in atomics. The last item of g14c."
---

# asm goto

Everything else in rump repro g14c compiles as of feature-c-inline-asm-rump-x86-operand-forms. This is the one remaining item.

## Done 2026-11-18 (x86-64)

The template is rewritten as text, so nothing new is needed in the encoder:
- Each `%lN` and `%l[name]` becomes the numeric local label `<99900+k>f`.
- After the template come the exit stubs: `movl $0,%slot; jmp 99899f`, then one stub per label `99900+k: movl $k+1,%slot; jmp 99899f`, then the `99899:` label.
- The slot is a hidden int local, bound as an "m" input to its own frame slot, so there is no copy in or out.
- After the block, CAsmGotoDispatch adds `if (slot == k+1) goto label_k;` per label, as ordinary AST. The labels resolve the usual way, forward or backward, and pruning sees normal gotos.

Refused by name:
- outputs (gcc's classic asm goto has none either);
- targets other than x86-64;
- a %l that names none of the statement's labels.

Test: test/c_inline_asm_goto.c, gcc's output at -O0 and -O2. It covers rump g14c's gz() verbatim, %l by number and by name, two labels, a never-taken label, and a backward jump (a loop). casm_goto_fails.c graduated: it compiles on x86-64 and is refused by name on i386.
