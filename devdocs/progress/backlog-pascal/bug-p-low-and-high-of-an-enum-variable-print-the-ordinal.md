---
slug: bug-p-low-and-high-of-an-enum-variable-print-the-ordinal
title: "`Low(a)` / `High(a)` where a is an enum variable print 0 and 2 where fpc prints the member names"
track: P
prio: 35
type: bug
status: backlog
owner: ""
created: 2026-09-05
found-by: frankB
blocked-by: []
summary: "`var a: D` for `D = (mon, tue, wed)`: `WriteLn(Low(a), ' ', High(a))` gives `0 2` where fpc gives `mon wed`. The ORDINALS are right and the RESULT NODE has forgotten which enum it came from. It is NOT an alias defect — the direct enum variable and the alias variable are equally wrong, which is what separates it from bug-p-a-type-alias-drops-the-enum-identity-and-a-set-drops-its-char-element-kind, whose alias half is fixed. The TYPE-NAME spelling `Low(D)` and `Low(TD)` both print member names, so the identity channel exists and reaches one of the two spellings."
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
