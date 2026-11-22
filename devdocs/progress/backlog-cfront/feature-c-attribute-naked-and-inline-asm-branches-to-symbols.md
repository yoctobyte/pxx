---
slug: feature-c-attribute-naked-and-inline-asm-branches-to-symbols
track: C
prio: 35
type: feature
status: backlog
created: 2026-11-22
found-by: claude-pxx (building micropython v1.24.1's unix port with pxx)
tags: [cfront, asm]
blocked-by: []
summary: "`__attribute__((naked))` is accepted and ignored, so the function still gets a prologue and epilogue. AT&T inline asm (asmatt.inc) can branch only to numeric local labels, not `jmp`/`call` a symbol. micropython's py/nlrx64.c needs both: its nlr_push is a naked function that tail-jumps to nlr_push_tail. The build used -DMICROPY_NLR_SETJMP=1 instead."
---

# `__attribute__((naked))`, and inline asm that branches to a symbol

## Found by

micropython v1.24.1, unix port, py/nlrx64.c:

```c
__attribute__((naked)) unsigned int nlr_push(nlr_buf_t *nlr) {
    __asm volatile (
        "movq   (%rsp), %rax  \n"
        ...
        "jmp    nlr_push_tail \n"
    );
}
```

Both features are needed together:

1. **naked**: no prologue or epilogue. pxx parses the attribute and drops it,
   so the asm runs with a pushed rbp and reads the wrong return address.
   gcc rejects anything in a naked function except basic asm. Supporting it
   means: no frame, no locals, no implicit return.
2. **A branch to a symbol**: `jmp sym` / `call sym` in asmatt.inc. Only `1f`/`1b`
   numeric labels are resolved today. It needs a relocation, or a fixup against
   the proc table, like an ordinary call.

Workaround in the scratch build: `-DMICROPY_NLR_SETJMP=1` (nlrsetjmp.c). That
build runs; it is slower than the asm path, nothing more.

Other ports have the same file per arch (nlrx86.c, nlraarch64.c, nlrthumb.c,
nlrxtensa.c, nlrrv32.c), so this is per-target work. x86-64 first.
