---
slug: bug-p-low-and-high-of-an-enum-variable-print-the-ordinal
title: "`Low(a)` / `High(a)` where a is an enum variable print 0 and 2 where fpc prints the member names"
track: P
prio: 35
type: bug
status: done
owner: ""
created: 2026-09-05
found-by: frankB
blocked-by: []
summary: "FIXED 2026-09-05. The diagnosis in this ticket was right: the ORDINALS were correct and the result node had forgotten which enum they came from. `TryOrdinalVarBound` -- the VARIABLE spelling -- reported a TTypeKind and nothing else, so the identity had nowhere to travel, while `TryFoldHighLowType` (the TYPE-NAME spelling) stamps ASTEnumId on the node it builds and was right all along. One out parameter, set in the enum arm and in the set-of-enum arm, stamped by both intrinsic call sites. `set of D` was a third face nobody had filed and is closed by the same parameter."
---

# Two spellings, one right

```pascal
type D = (mon, tue, wed); TD = D;
var a: D; b: TD;
WriteLn(Low(D),  ' ', High(D));    { mon wed — correct }
WriteLn(Low(TD), ' ', High(TD));   { mon wed — correct as of 2026-09-05 }
WriteLn(Low(a),  ' ', High(a));    { 0 2  — fpc: mon wed }
WriteLn(Low(b),  ' ', High(b));    { 0 2  — fpc: mon wed }
```

Found while fixing the enum half of the alias-identity ticket, and deliberately
NOT folded into it: that one was about a fact lost at the alias registration
boundary, and this one loses nothing at a boundary — the direct enum variable is
wrong too.

# Where to look

`TryFoldHighLowType` / `TryConstHighLowValue` handle the TYPE-NAME spelling and
both stamp the identity (`ASTEnumId[outNode] := etid`, `CEEnumId := etid`). The
VARIABLE spelling is answered elsewhere, in the `high`/`low` arm of
pasparser_expr.inc, and that arm has the symbol — which carries `SymEnumId` —
so the fact is present and simply not stamped on the result node.

The type-name arms are the model: they had exactly this bug and their fix is one
line each, with a comment saying *"the ordinal was right and the node simply
forgot which enum it came from"*.

# RESOLVED 2026-09-05

`TryOrdinalVarBound` gained `eidOut`. Set in two arms — the enum variable
(`SymEnumId`) and the set whose ELEMENT is an enum (`SymSetEnumId`) — and read
by both the `High` and the `Low` arms in `pasparser_expr.inc`, which stamp
`ASTEnumId` exactly as `TryFoldHighLowType` already did for the type name.

**The ticket called this right, and the reason is worth keeping.** It said the
identity channel *exists and reaches one of the two spellings*. That is the
diagnosis that made the fix a parameter rather than a search: the question was
never "how does an enum bound carry its type", it was "why does one of two
spellings of one intrinsic have no way to say the answer it already has".

A THIRD face nobody had filed: `set of D`. `Low(u)` printed 0 where fpc prints
mon, same missing channel one level down on the element. It is in the same
routine and would have been left behind by a fix scoped to the ticket's own
example — the enum VARIABLE — which is the argument for probing the construct
rather than the reported row. The full probe was nine spellings and five were
wrong; the ticket named two of the five.

Closed together with [[bug-p-a-set-of-a-char-subrange-drops-its-element-kind]],
which is the same intrinsic and a completely different mechanism — two tickets
that read as one family by their symptom and share no code.

Test: `test/test_low_high_carry_the_ordinals_identity.{pas,expected}`, 15 rows,
fpc oracle.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
