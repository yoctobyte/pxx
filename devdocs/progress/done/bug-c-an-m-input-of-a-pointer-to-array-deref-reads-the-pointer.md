---
track: C
tags: [c, inline-asm, x86-64, silent-miscompile]
prio: 10
type: bug
blocked-by: []
summary: "An inline-asm \"m\" INPUT of `*(T (*)[N])p` (or `*q` for q a pointer-to-array) handed the template a stack copy of the POINTER, not the array: `movq %1,%0` with \"m\" (*(const long (*)[2])a) returned a's address. frstor/fxrstor/xrstor in NetBSD's cpufunc.h would have restored FPU state from a pointer's bytes."
status: done
owner: claude-dupwt
---

# An "m" input of a pointer-to-array deref read the pointer

Found while making NetBSD's cpufunc.h assemble
([[feature-c-inline-asm-x87-and-system-instructions]]): the disassembly showed
`frstor -0x20(%rbp)`, a stack slot, where gcc reads through the pointer.

## Cause

C makes `*q` for a pointer-to-array the array, which decays straight back to
the same address. pxx builds it as the decay node `q + 0`, not an AN_DEREF. The
inline-asm operand binder takes an "m" input by ADDRESS only for AN_DEREF,
AN_INDEX and AN_FIELD; everything else gets a carrier temp holding the
expression's VALUE, and %N names that temp. Here the value is the address, so
the template read the pointer. Outputs were already right, because every
x86-64 "m" output is bound by address.

Silent: it compiles, and with an fxrstor it restores garbage FPU/SSE state.

## Fix

`CAsmIsPtrToArrDeref` (cparser.inc) recognises the decay node, both the
stamped form and a cast's `(t = e, t) + 0`, and the binder takes it by address
as it does `*p`.

`test/c_inline_asm_x87_and_system.c` checks a cast, a plain pointer-to-array
parameter and an output (the "m input" lines), against gcc.
