---
slug: bug-c-an-m-operand-dereference-on-i386-still-binds-a-copy
track: C
prio: 40
type: bug
status: done
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, inline-asm, toybox]
blocked-by: []
summary: "The ATTBIND_MEMREG fix is x86-64 only: on i386 an \"m\" input that is a dereference still binds a frame-slot copy, so clflush/lock RMW act on the copy."
---

# i386: "m" dereference binds a copy

The i386 text sink needs a `(reg)` operand form. See the done ticket bug-c-an-m-operand-that-is-a-dereference-binds-a-copy.

## Done 2026-11-19 (rd)

The `(reg)` form was already there: AttRender386 writes AOP_MEMR as
`dword [reg]`, and asmtext_386 parses it. What kept i386 on the copy was
two gates in CAsmBuildBlock that said TARGET_X86_64, and an 8-byte address
load. Both now admit i386, and the address load uses TARGET_PTR_SIZE.

Measured. Before, on latest, `addl %1, %0` with "m"(*p) added to a stack
copy (tot stayed 100) and `movb $7, %0` set a copy (c stayed 1). Silently:
the program printed `7 99 41 100 1` where gcc -m32 prints `7 99 43 123 7`.
pxx now prints gcc's at -O0 and -O2 (test/c_inline_asm_m_deref_i386.c,
test-core rows c_asmmderef386 and c_asmmderef386_o2). casm_gnu_operands_i386
is unchanged against gcc -m32.

Left as it was, on purpose:
- An "=m" OUTPUT on i386 keeps its copy. It is stored back after the block,
  so the right object is written, and binding the address would take one of
  the five pool registers the busybox blocks need.
- `lock` and a memory `inc`/`dec` are still refused by name on i386: the
  i386 text engine does not encode them. That fails loudly, so it is not
  this bug.
