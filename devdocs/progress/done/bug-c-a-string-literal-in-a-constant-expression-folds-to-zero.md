---
slug: bug-c-a-string-literal-in-a-constant-expression-folds-to-zero
track: C
prio: 50
type: bug
status: done
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, toybox]
blocked-by: []
summary: "`static const int X = \"s\" || 0;` folded to 0 because CEvalConstPrimary had no string arm. A string literal is a non-null address constant; it now evaluates to 1 (adjacent literals consumed). toybox's NEED_OPTIONS is spelled this way, so option parsing was compiled out."
---

# C: a string literal in an integer constant expression

Fixed in CEvalConstPrimary (cparser.inc). Covered by
`test/c_toybox_compiler_shapes.c`.
