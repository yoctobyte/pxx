---
slug: bug-c-a-c99-inline-function-in-a-header-is-a-strong-symbol-in-every-object
track: C
prio: 55
type: bug
status: backlog
created: 2026-11-16
found-by: pixx-cc, building disk tools for pixx at 2491105c8d (repros: /data/projects/pixx/work/tooltest/repro/) B4
tags: [cfront, emit-obj, link]
blocked-by: []
summary: "A C99 `inline` (not static, not extern) definition in a header is emitted as a strong symbol in every object, so two objects that include it fail at --link with multiple definition. C99 6.7.4: a plain inline definition provides no external definition; gcc emits nothing (or a weak/COMDAT copy under gnu89). Repro c99inline_a.c/c99inline_b.c."
---

## Fixed 2026-11-19 (pxx2)

The lexer used to drop `inline` without a trace. It now marks the next token
(CAttrFlags bit $400), and `__attribute__((gnu_inline))` gets bit $800.
CNoteInlineLinkage applies C99 6.7.4p7 to each file-scope declaration and
definition of a function:
- An inline definition (`inline`, neither static nor extern) sets ProcCInlineDef.
- Any declaration with `extern`, or without `inline`, sets ProcCExtDecl,
  whether it comes before or after the definition.
- gnu_inline reverses the rule: `extern inline` sets ProcCGnuExtInline and
  never becomes external; a plain `inline` definition is external.

The flags are only ever set, so the result does not depend on declaration
order or on which parse pass runs. CProcInlineOnly gives the ELF and PE writers
a LOCAL symbol where gcc emits none at all; a local copy links the same way.
Nothing else reads the flags, so calls and the C module row-splitting rules
are unchanged.

Tests:
- test/c_inline_hdr.h with c_inline_hdr_a.c and c_inline_hdr_b.c (row
  c_inlhdr26) link two objects that include the header. The old compiler
  printed "1 multiply defined symbol(s)"; the output now matches gcc.
- test/c_inline_linkage.c (c_inllink-binding, c_inllink26) covers 8 cases:
  every gcc T is a pxx T, and every gcc t-or-absent is a pxx t.
