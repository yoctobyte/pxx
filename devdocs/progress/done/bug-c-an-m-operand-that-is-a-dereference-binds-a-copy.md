---
slug: bug-c-an-m-operand-that-is-a-dereference-binds-a-copy
track: C
prio: 70
type: bug
status: done
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, inline-asm, toybox]
blocked-by: []
summary: "An inline-asm \"m\" INPUT that is a dereference (`\"m\"(*p)`, `a[i]`, `s->f`) was bound to a frame-slot copy of the value, so `lock incl %0` incremented the copy and `clflush %0` flushed a stack temp. On x86-64 the address now goes into a pool register and %N renders as `(reg)` (ATTBIND_MEMREG). Found from Gibux vtd.c."
---

# C inline asm: "m" on a dereference

cparser.inc CAsmBuildBlock + asmatt.inc ATTBIND_MEMREG. x86-64 only; i386 keeps
the copy (backlog: bug-c-an-m-operand-dereference-on-i386-still-binds-a-copy).
Test: `test/c_inline_asm_m_deref_and_clflush.c` at -O0 and -O2.
