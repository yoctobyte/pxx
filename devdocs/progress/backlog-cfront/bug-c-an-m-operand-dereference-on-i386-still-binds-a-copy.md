---
slug: bug-c-an-m-operand-dereference-on-i386-still-binds-a-copy
track: C
prio: 40
type: bug
status: open
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, inline-asm, toybox]
blocked-by: []
summary: "The ATTBIND_MEMREG fix is x86-64 only: on i386 an \"m\" input that is a dereference still binds a frame-slot copy, so clflush/lock RMW act on the copy."
---

# i386: "m" dereference binds a copy

The i386 text sink needs a `(reg)` operand form. See the done ticket bug-c-an-m-operand-that-is-a-dereference-binds-a-copy.
