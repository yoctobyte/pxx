---
slug: bug-c-a-define-inside-a-multi-line-expression-applies-to-the-text-before-it
track: C
prio: 50
type: bug
status: done
owner: pxx2
created: 2026-11-20
closed: 2026-11-20
found-by: pxx2, building libXt for the Path B JWM desktop
tags: [cfront, preprocessor]
summary: "While a parenthesis is open, CPProcessText joins physical lines and expands the joined line after obeying every directive inside it. So an `#undef X / #define X` in the middle of an `if (...)` rewrote the text before it. That is now done only inside a function-like macro call's argument list (CPOpenParenIsMacroCall); an ordinary parenthesis is expanded up to the directive first. test/c_define_inside_expression.c (c_defexpr26)."
---

# A #define inside a multi-line expression applied to the text before it

libXt's Shell.c (WMSetValues) redefines `NEQ` between two halves of one
`if (set_prop && (NEQ(flags) || ...` condition. Every `NEQ` in it took the
last definition, which gave "no member named 'flags'". A reduction by
function definitions found the shape, and a 15-line repro confirmed it. The
busybox case (`# if` inside getopt32long's arguments) still collects and
continues, and the test checks it.
