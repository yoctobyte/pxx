---
slug: bug-p-sizeof-through-a-pointer-to-a-string-n-answers-pointer-width
track: P
prio: 45
type: bug
status: working
owner: frankB
created: 2026-09-06
found-by: frankS
blocked-by: []
title: "`SizeOf(p^)` for a `^string[10]` answers 8 where fpc says 11 — the deref shape the 2026-09-02 capacity fix did not reach"
summary: "`bug-p-sizeof-answers-pointer-width-for-a-string-n-that-occupies-more` (frankB, done 2026-09-02) taught SizeOf the capacity for a type name, a variable, an array and an element. The POINTER-DEREF shape was not in its table and still answers pointer width: `SizeOf(p^)` for `p: ^string[10]` gives 8 against fpc 3.2.2's 11, in BOTH declaration orders and for both the `PT = ^TT; TT = string[10]` and the direct `PT = ^string[10]` spellings — so it is not the forward-resolution defect fixed the same day, which was order-dependent. Cause is one line: a `^` anywhere in the operand routes SizeOf down its EXPRESSION path (pasparser_expr.inc, `szIsExpr`), and that path's fallthrough is `TypeSlotSize(szExprTk)`, which takes a kind and no capacity. Every other shape reaches FrozenStrSlotSize(tk, cap). The capacity is available — AliasPtrStrCap for an alias-spelled pointer, SymPtrElemStrCap for a variable's — and the expression path already has three precedents for asking a shape-specific sizer before that fallthrough (DerefPtrArrayInfo for a pointer-to-array, RecFieldByteSize for `p^.f`, RecSize for a pointer-to-record). This is the fourth. Reaches a value the same way its parent did: `FillChar(p^, SizeOf(p^), 0)` clears 8 of 11 bytes."
---

# Measured 2026-09-06, compiler `c73cfd487af1` (commit 393fe0184)

```pascal
type TT = string[10];  PT = ^TT;      { and the reverse order, and PT = ^string[10] }
var v: TT; p: PT;
SizeOf(v)   -> 11  = fpc      { frankB's fix }
SizeOf(p^)  ->  8    fpc 11   { this ticket }
p := @v; v := 'abc'; p^ and Length(p^) are both CORRECT
```

The VALUE through the pointer is right; only the size is wrong. That is what
makes it the `FillChar`/`Move` shape rather than a visible one.

## Why it is filed and not folded into the forward-pointer fix

Found while fixing `ResolvePendingPointerAliases`' scalar/set arm, whose whole
signature is *order-dependent*. This one is not: the in-order spelling answers 8
as well, so it was never the pending-alias pass's business. Folding it in would
have put a second, unrelated cause under one commit's positive control.
`test_a_forward_pointer_to_a_scalar_or_set_alias_keeps_its_pointee.pas`
deliberately asserts the STORE through a `^string[4]` and not the SizeOf, so it
makes no claim it cannot keep.
