---
slug: bug-c-return-of-a-comma-expression-is-refused
track: C
prio: 60
type: bug
status: done
owner: pxx2
created: 2026-11-26
closed: 2026-11-26
found-by: pxx2 (Nodisx curl + mbedTLS recipe)
tags: [cfront, parser]
summary: "`return a, b;` -- the comma operator directly in a return -- was 'expected C expression': the return statement parsed one assignment expression (ParseCExpr). It now parses a full expression (ParseCCommaExpr), as if/while/for conditions already did. `return (a, b);` always worked. Test c_retcomma26 against gcc."
---
# `return a, b;` was refused

Found writing curl's accept4 test, in the idiom
`if (s < 0) return printf("failed\n"), 1;`. C's return takes an
*expression*, which includes the comma operator; pxx's `return` called
`ParseCExpr`, which stops at a comma because it is also what function
arguments and initialisers use.

## Fix

The return path calls `ParseCCommaExpr`, which builds `AN_COMMA` (left for
its effects, value from the right) and was already used for if/while/for
conditions and for the parenthesised form.
