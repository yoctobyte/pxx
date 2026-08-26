---
track: N
prio: 40
type: bug
blocked-by: []
summary: "Found by inspection, NOT reproduced: NodeEnumIdOf's call arm and PyEvalOnce's chained-receiver test both match AN_CALL without AN_VIRTUAL_CALL, so a VIRTUAL method call loses its enum result identity and a chained call receiver is re-evaluated per link. Both predate the dunder-dispatch fix that surfaced them."
---

# Two node consumers know `AN_CALL` but not its virtual sibling

Filed 2026-08-26 while fixing
[[bug-n-a-subscript-inside-a-base-class-skips-the-subclass-override]].

**Honest status: found by grep, not by a failing program.** Neither line below
has been turned into a repro, and the priority reflects that. Do not write a
symptom into this ticket that has not been measured.

## The pattern

`AN_CALL` and `AN_VIRTUAL_CALL` carry the callee's proc index in the same field
(`ASTIVal`); the virtual one additionally holds its VMT slot in `ASTRight`. Most
consumers therefore test both, and the codebase spells it
`(ASTKind[n] = AN_CALL) or (ASTKind[n] = AN_VIRTUAL_CALL)` in `ir.inc`,
`symtab.inc`, `ast_arena.inc` and several places in `pasparser_lval.inc`.

Two do not:

| site | test | what the sibling arm does for `AN_CALL` |
| --- | --- | --- |
| `pasparser_expr.inc:9023` (`NodeEnumIdOf`) | `ASTKind[node] = AN_CALL` | reads `ProcRetEnumId[ASTIVal[node]]` — "a call node has no symbol and no field, so the callee's row is the only place the result's enum identity survives" |
| `pyparser.inc:35419` | `(ASTKind[node] = AN_CALL) and (CurTok.Kind in [tkDot, tkLBrack])` | binds the receiver to a hidden temp via `PyEvalOnce`, because an IR value node is a SUBTREE and reusing one RE-EMITS the expression |

If the reasoning in those two comments is right, then for a **virtual** call the
first loses the enum identity of a method result (so `if obj.kind() == Red`
compares against something with no enum row), and the second re-evaluates the
receiver once per chain link (`obj.make().a.b`) — which that site's own header
calls out as silent, and worse the longer the chain.

## Why it is not attributable to the dunder-dispatch fix

`PyParseMethodCallArgs` has emitted `AN_VIRTUAL_CALL` for a hierarchy class
since virtual slots landed, so `obj.make()` has been a virtual call all along.
The dunder fix widened *which* nodes are virtual; it did not create the
asymmetry. Confirm against pinned v376 before treating any repro as a
regression.

## First step

Write the two repros — an enum-returning method on a class with a subclass, and
a chained call on the same — and measure them on pinned v376. **If they pass,
the comments are describing a hazard that some other mechanism already covers,
and the right outcome is to close this ticket saying so.** That is a real
possible answer here; a grep finding is a hypothesis, not a bug.

## Gate

Whatever the repros show. If it is a bug: both sites accept both kinds, plus a
`test-core` row per site pairing the non-virtual arm with the virtual one,
`.expected` from CPython.
