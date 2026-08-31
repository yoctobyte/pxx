---
slug: bug-a-shr-reaches-the-ir-spelled-as-tkident
title: "`shr` reaches the IR spelled Ord(tkIdent), and each consumer has to know that separately"
track: A
prio: 60
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-08-28
summary: "The Pascal lexer never produces tkShr — it lexes `shr` as an identifier — so an IR_BINOP carrying Pascal shr carries Ord(tkIdent) in its operator field. But tkShr DOES exist and the C lexer produces it correctly (clexer.inc:871), so one IR operator field means two different things depending on which frontend built the node, across 25 sites. ir.inc:9518 substitutes for exactly one consumer; ir_codegen_wasm32.inc:1276 is the second arm. Normalise at IRAppend. Repriced 20 -> 60 on 2026-08-31: eight shr tickets have been closed individually since 2026-06-26 and this is upstream of that family, but none of them declared a blocked-by edge to it (seven predate it), so prio propagation could never see it."
---

# The shape

`compiler/ir.inc:9507` says it plainly:

```
{ Pascal spells `shr` as an IDENTIFIER — there is no tkShr token for it }
...
if item = Ord(tkIdent) then item := Ord(tkShr);     { :9518 at HEAD }
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

---

## 2026-08-31 — corrected, and repriced 20 → 60 (owner)

**The premise sentence was half wrong, in the direction that understates it.**
This ticket said *"there is no `tkShr` token for it"*. `tkShr` **exists**, and
`compiler/clexer.inc:871` produces it correctly:

```pascal
begin Inc(SrcPos); CurTok.Kind := tkShrEq; end
else CurTok.Kind := tkShr;
```

So this is not "a token we never minted". It is **one IR operator field meaning
two different things depending on which frontend built the node** — `Ord(tkShr)`
from C, `Ord(tkIdent)` from Pascal — read by 25 `tkShr` sites across the
compiler. A consumer that handles `Ord(tkShr)` is *correct for C code and
silently wrong for Pascal code*, in the same binary, at the same site. That is a
strictly stronger statement of the bug than "each consumer has to know
separately", and it is the reason the fix is normalisation rather than tidying.

Line numbers refreshed: the substitution is at `ir.inc:9518` (was cited as
:8878) and the comment at `:9507` (was :8867). Still live at HEAD; the wasm32
second arm is still at `ir_codegen_wasm32.inc:1276`.

**Why the reprice, and it is a ranking finding, not a judgement about this
bug.** `shr` has produced **ten** tickets. Eight are closed, individually,
between 2026-06-26 and 2026-08-25, priced 30-60:

```
bug-cardinal-expr-promotion-shr-orphan            bug-a-strict-fpc-shr-by-zero-drops-the-sign
bug-const-expr-shl-shr-not-folded                 bug-a-unary-minus-binds-looser-than-and-shr
bug-shr-signed-integer-width                      bug-a-shr-on-a-32-bit-operand-does-not-promote-like-fpc
bug-a-promoint-shr-yields-nothing-...             bug-a-variant-shr-is-arithmetic-where-static-shr-is-logical
```

This ticket — upstream of that family — sat at **20**, the lowest prio of all
ten. That is not a mistake anyone made. **Prio propagates only down declared
`blocked-by:` edges, and seven of the eight symptoms were filed BEFORE this
ticket existed, so they could never have declared one.** The ranker reads one
ticket at a time and has no way to see the shape of a pile. Tooling follow-up:
`feature-t-detect-ticket-clusters-that-share-a-construct`.

