---
slug: bug-a-shr-reaches-the-ir-spelled-as-tkident
title: "`shr` reaches the IR spelled Ord(tkIdent), and each consumer has to know that separately"
track: A
prio: 20
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-08-28
summary: "Pascal's shr is lexed as an identifier — there is no tkShr token for it — so an IR_BINOP carrying shr carries Ord(tkIdent) as its operator. ir.inc:8878 substitutes Ord(tkShr) for exactly one consumer. Every other consumer must repeat that substitution or silently mistake `shr` for whatever it does with tkIdent. The wasm32 backend is now the second arm; normalise at IRAppend instead."
---

# The shape

`compiler/ir.inc:8867` says it plainly:

```
{ Pascal spells `shr` as an IDENTIFIER — there is no tkShr token for it }
...
if item = Ord(tkIdent) then item := Ord(tkShr);     { :8878 }
```

That substitution is correct and local. The problem is that it is local: the
token that reaches `IR_BINOP`'s operator field is still `Ord(tkIdent)`, so the
normalisation is a property of one reader rather than of the IR.

# Why it is worth a ticket rather than a shrug

`devdocs/dev/normalise-dont-special-case.md`: when a construct is reachable
through two shapes, normalise rather than growing a second path, *because the
second path is the one that stays broken*. There is now a second path. The
wasm32 backend (branch `wasm`, `compiler/ir_codegen_wasm32.inc`) repeats the
substitution with a comment pointing here.

The failure mode for a consumer that does not know is worse than a missing
feature: `tkIdent` is not an unlikely value that would obviously fall through to
an "unsupported operator" arm. It is token 1. Any consumer that dispatches on a
small operator ordinal, or that treats an unrecognised operator as a default,
can quietly do the wrong thing for every `shr` in the program.

# Fix

Substitute at the point the `IR_BINOP` node is appended, so the IR carries
`Ord(tkShr)` and no consumer has to know the lexer's accident. Then delete the
substitution at ir.inc:8878 and the one in ir_codegen_wasm32.inc, and grep for
others — per the doc's own rule, fixing one arm of a double case means checking
the sibling before closing.

Genuinely low prio: nothing is wrong today, both current consumers handle it.
The value is that the next one cannot get it wrong, and the fix deletes code
rather than adding it.

# Found

By the wasm32 backend, 2026-08-28: `shr` showed up in the coverage report as
`binary operator 1`, which is how the lexer accident became visible at all.
