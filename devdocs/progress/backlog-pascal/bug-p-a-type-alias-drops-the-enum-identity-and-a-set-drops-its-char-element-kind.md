---
track: P
prio: 40
type: bug
blocked-by: []
summary: "Two measured losses of a type's IDENTITY at a registration boundary, both pre-existing on pin v403. (1) `type TDays = D` where D is an enum: a variable declared through the ALIAS prints its ORDINAL where fpc prints the member name -- `WriteLn(a)` gives `1`, not `tue` -- because enums are tyInteger plus an id and the alias table has no column for the id. The same variable's `case` still works, since members resolve globally, which is what hides it. (2) `Low`/`High` of a `set of 'c'..'k'` answer 99 and 107 where fpc answers c and k: the element's CHAR kind is dropped. The BOUNDS half was a SECOND defect and is FIXED (2026-09-05): the bounds survived only in the INLINE spelling -- through `type TCS = set of 'c'..'k'` they were lost too and Low/High answered 0 and 255, the element type's full range. The remaining open half is the element KIND on the inline spelling, which is the decide-fork's business. Same family as the AliasStrCap / AliasStrElemTk / AliasFileElemTk gaps already fixed in RegisterGeneralAlias -- a fact that is live in a LastType* channel at registration and has nowhere to be written."
---

# A type alias drops the enum identity; a set drops its char element kind

Both found while fixing
[[bug-p-a-subrange-bound-must-be-a-literal-token]] (landed 2026-09-05), both
verified PRE-EXISTING against pin v403, and neither caused by that change.

## 1. An alias to an enum loses the member names

```pascal
type D = (mon, tue, wed);
     TDays = D;
var a: TDays; b: D;
...
b := wed;  WriteLn(b);   { pxx: wed   fpc: wed  }
a := tue;  WriteLn(a);   { pxx: 1     fpc: tue  }
           WriteLn(mon); { pxx: mon   fpc: mon  }
```

A direct enum variable and a bare member literal both print correctly. Only the
variable declared through the ALIAS falls back to the ordinal.

**Cause, read rather than guessed:** an enum is not a `TTypeKind` in this
dialect — an enum symbol is `tyInteger` with `SymEnumId >= 0` (the convention
`CEEnumId`'s own declaration in defs.inc states). `RegisterGeneralAlias` records
`AliasTk = tyInteger` and there is no `AliasEnumId` column, so the identity has
nowhere to go. `ParseTypeKind` has just run and left it in `LastTypeEnumId`,
which is exactly the window `AliasStrCap`, `AliasStrElemTk`, `AliasFileElemTk`
and (since 2026-09-05) `AliasIsSub` all read from — this is the same gap those
each were, one type over.

**Why the obvious test misses it:** `case a of mon: ...` works, because enum
members are resolvable globally rather than through the variable's type. So
every control-flow use of the alias behaves, and only the WriteLn formatter —
which needs the id to find the name table — shows it.

A NAMED subrange of an enum (`type TW = sat..sun`) has the same hole for the
same reason; the INLINE spelling (`var v: sat..sun`) prints the member name
correctly today, because there `LastTypeEnumId` reaches the symbol directly.
That asymmetry is a good positive control for a fix.

## 2. Low/High of a set of a char subrange answer numbers

```pascal
var b: set of 'c'..'k';
WriteLn(Low(b), ' ', High(b));   { pxx: 99 107    fpc: c k }
```

The BOUNDS survive (99 and 107 are right) — it is the element KIND that is
dropped, so the values print as integers. `set of 1..10` and `set of sat..sun`
are correct, the latter only because the probe reads it through `Ord`.

`ParseSetElemSpec` has its own copy of the subrange parse guarded on
`tkInteger`, so a char subrange element takes the `else ParseTypeKind()` branch
and the set's element kind is recorded from a path that did not set it. That
copy is the last of the three "parse lo..hi" copies — the other two were folded
into one shared body on 2026-09-05 — and folding it is the likely fix, but it
was left alone because the verification needs its own pass: `Low`/`High` of a
set TYPE NAME (as opposed to a set VARIABLE) is refused outright here
(`undefined variable (SI)`), so half the natural assertions are unavailable
until that is settled too.

## Suggested order

(1) first: it is one column plus the read sites, and it has a clean positive
control in the inline-vs-alias asymmetry. (2) wants the third subrange copy
folded, and wants the set-type-name `Low`/`High` question answered first.

## The fork is filed

[[decide-how-a-type-carries-an-identity-its-kind-cannot-hold]] (Track U, p55)
names this and the sized-boolean bug as the two families ONE mechanism would
close, and recommends the side-channel arm — which is this ticket's suggestion
(1) generalised. Settle that first; the carry sites are shared.

## 2026-09-05 — (2) re-measured at a moving tip, and split into three

frankA's "both bugs still reproduce" row was stamped at `167847e61`, before the
`{$H-}` commit touched `pasparser_decl.inc` and `pasparser_expr.inc`; they said
so and stood down rather than re-take it. Re-taken here at tip `e9a885ba2`,
compiler `ba573b6cf02a`. Row 1 reproduces exactly as written. Row 2 is not one
defect but **three**, and the ticket above had measured only the first spelling:

| spelling | Low/High bounds | element kind |
| --- | --- | --- |
| `var b: set of 'c'..'k'` (inline) | **99 107 — right** | dropped, prints ordinals |
| `type TCS = set of 'c'..'k'` (alias) | **0 255 — WRONG** | dropped |
| `Low(TCS)` on the TYPE NAME | refused: `undefined variable (TCS)` | — |

All three confirmed pre-existing against the pinned compiler.

**The bounds half is FIXED.** `ParseSetElemSpec` sets `elemLo := 0; elemHi := -1`
and captures bounds only inside its `tkInteger` arm, so a subrange spelled any
other way took `else elemTk := ParseTypeKind()` and registered `Hi < Lo` — "not
a subrange" — after which `Low`/`High` fell back to the element TYPE's range.
`ParseTypeKind`'s own subrange tail had already left the correct bounds in
`LastTypeSubLo`/`Hi`, live and one line away, unread. Only the NAMED spelling
was wrong because only it reaches that branch. The fix reads the channel that
was already correct; it is four lines and adds no column.

**This does not pre-empt [[decide-how-a-type-carries-an-identity-its-kind-cannot-hold]].**
The bounds are needed under EITHER arm of that fork — a side channel and a new
`TTypeKind` both still have to know that the element range is 99..107 — so
capturing them here decides nothing. The element KIND is the half that needs the
fork, and it is untouched.

**Attribution, by ablation.** Removing the fix and rebuilding reproduced
`ba573b6cf02a` byte-identically and put back exactly two rows: char alias
`99 107` -> `0 255`, enum-subrange alias `1 2` -> `0 3`. **The ablated build
still COMPILED the probe**, so the pin's `unknown type: sun` refusal was fixed
earlier by someone else and is NOT claimed here.

Test: `test/test_set_elem_bounds.pas` + `.expected` (fpc 3.2.2's own output,
seven rows). The inline rows are the control — they were right before the fix,
so a run checking only the alias rows cannot tell a fix from a coincidence. The
`alias chars ck` row is the element kind surviving the ALIAS path, which is why
the two halves are separable at all: the inline spelling still prints `99107`
there and stays open.

**Still open on (2):** the element KIND on the inline spelling (fork), and
`Low`/`High` of a set TYPE NAME being refused outright.
