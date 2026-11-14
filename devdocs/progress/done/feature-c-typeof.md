---
slug: feature-c-typeof
track: C
prio: 40
type: feature
status: done
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, toybox]
blocked-by: []
summary: "`typeof(expr)` / `__typeof__(expr)` / `typeof(type)` in declarations, for arithmetic expressions and type names. Pointer, struct and untyped expressions are refused with a diagnostic rather than guessed."
---

# C: typeof

toybox's lib uses `typeof` in its min/max macros. `CIsTypeofWord` makes the
spelling a type token; the arm in ParseCDeclType parses a type name directly, or
types an expression without evaluating it and takes its scalar kind. A pointer,
record or unknown-typed expression is refused (the declared shape would be
guessed otherwise). Test: `test/c_toybox_compiler_shapes.c` (x86-64, i386,
aarch64, arm32; expected = gcc).
