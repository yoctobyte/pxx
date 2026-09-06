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


## Resolved 2026-09-06 — frankB, Group 19 ("how many bytes is this type", asked through a door that never reaches the capacity table)

Fixed, and **not the way this ticket proposed.** The ticket said the expression
path already consults three shape-specific sizers before its fallthrough and
this is the fourth. It is the fourth arm, but the arm the ticket described
would have been WRONG, and the reason is the group's whole finding.

### The obvious repair answers 24, not 11

`SizeOfSlot(szExprTk, FrozenStrCapOfDeref(node))` supplies the missing capacity
and leaves the kind alone. **An ident node for a frozen string carries the
legacy overloaded `tyString` whatever the symbol holds** — measured on the
sibling ticket with a `PXXDBG p.fiosize` probe, `nodeTk=4 symTk=25 symCap=10`,
and confirmed here with a `p.szexpr` probe printing `tk=4` for both a
`^string[10]` and a `^string[300]`. `tyString`'s length prefix is eight bytes
and a shortstring's is one, so that spelling answers `AlignTo(10+8,8) = 24`.
A loud wrong answer replacing a quiet one.

### Both facts were already recorded, on the same symbol

    Syms[sym].PtrElemTk      the pointee's KIND      probed: 25 / 26
    SymPtrElemStrCap[sym]    the pointee's CAPACITY  probed: 10 / 300

`DerefFrozenStrSlotSize` (symtab.inc, beside `FrozenStrCapOfDeref`) reads both
out of that one symbol and calls `SizeOfSlot`. It is deliberately one function
rather than a capacity reader plus a kind reader at each call site — the
invariant the group established is that **the kind and the capacity must come
out of the same record**, and a helper is where an invariant can be stated once.

### Why the wide kind is in the test

`string[N]` is `tyShortString` up to 255 and `tyFixedString` above it, and
`tyFixedString`'s prefix is also eight bytes. So the wrong kind is right by
coincidence above the boundary, and a test that only carries `string[10]`
cannot tell a correct sizer from a lucky one. Row G asserts 312 for a
`^string[300]`.

### Verified

| row | | pxx | fpc 3.2.2 |
| --- | --- | --- | --- |
| A | `PT = ^TT; TT = string[10]` | 11 | 11 |
| B | `PE = ^TU; TU = string[7]` (pointer declared first) | 8 | 8 |
| C | `PS = ^string[10]` direct | 11 | *refused: local type definition* |
| G | `PW = ^TW; TW = string[300]` | 312 | *refused: shortstring capped at 255* |
| D | `SizeOf(v)` control | 11 | 11 |
| E | `FillChar(p^, SizeOf(p^), 0)` then `Length(v)` | 0, guard intact | 0, guard intact |
| F | `Move(p^, g, SizeOf(p^))` | whole slot | whole slot |

Rows A, B, D, E, F are byte-identical to fpc's own output for the same program.
E and F are the consequence rather than the number: before the fix the FillChar
cleared 8 of 11 bytes.

`make compiler/pascal26`: `converged after 1 round(s)`.

### One correction to this ticket's own body

It says the defect reproduces "for both the `PT = ^TT` and the direct
`PT = ^string[10]` spellings", which is true of us and reads as though both are
FPC-comparable. They are not: **fpc refuses `^string[N]` in a type block
outright** — `Parameters or result types cannot contain local type definitions`
— so the direct spelling is ours alone and has no oracle. Noted because the
ticket's evidence is otherwise stated against fpc.
