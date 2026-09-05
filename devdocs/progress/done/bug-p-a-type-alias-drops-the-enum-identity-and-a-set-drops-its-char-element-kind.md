---
track: P
prio: 40
type: bug
blocked-by: []
summary: "FIXED (the enum half; the set-of-char half is split out as [[bug-p-a-set-of-a-char-subrange-drops-its-element-kind]] and this ticket no longer covers it). `type TDays = D` now carries the enum's IDENTITY through the alias: a variable, an alias chain, a record field, a value and a var parameter, a function result, an array element and the ordinal operators all print member names, and `Low(TDays)`/`High(TDays)` answer mon/thu instead of INT_MIN/INT_MAX. One new column in RegisterGeneralAlias — the SIXTH fact in a list whose five neighbours each say `same window and same reason`, and the one that was never written."
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


# Resolved — the enum half

## One column, and the reason it was missing is the finding

`RegisterGeneralAlias` carries five facts out of the `LastType*` channels: a
frozen string's capacity, a subrange's bounds, a file's element width, a managed
string's element width, a pointer's target. Each is its own guarded block, and
four of the five say some version of *"exactly AliasStrCap's problem one type
over"*. The enum id is the sixth and **nobody wrote it**.

That is the omission class arriving inside the duplication class. Reading the
five copies against each other cannot find the sixth, because **they agree** —
the instrument for a missing caller is the callee's own contract, not a diff of
its callers.

## AliasEnumId is stored +1, and on purpose

Its five neighbours use 0 as "not one" because 0 is not a valid capacity or
kind. **0 IS a valid enum index**, so an unwritten row would read as enum 0 —
and an unwritten row is precisely how this fact went missing. With the bias, a
registration site that forgets the column yields NONE and the omission is inert
rather than silently wrong. Six sites call `Inc(AliasCount)`; only one of them
needed to learn anything.

## The guard is EnumKindMatches, not `LastTypeEnumId >= 0`

`set of TCol` leaves the ELEMENT's id in that global. Capturing unguarded would
stamp a SET alias with its element's identity and print a bitset as a member
name. `EnumKindMatches` is the predicate seven other sites already use for
exactly this question, and its own header records that the kind test *"is the
only thing stopping a set from inheriting a member name"*. This is its eighth
caller, and `CONTROL set alias` in the test is the row that fails without it.

Its forward declaration MOVED from `pasparser_name.inc` to `symtab.inc`'s
existing forward block rather than being duplicated: a duplicate forward across
two `.inc` files builds clean, passes `--tier quick`, and is caught only by the
FPC seed canary — a class CLAUDE.md names by that description. The canary passed.

## Low/High of the alias NAME was a second site, and a double case

`Low(TDays)` answered -2147483648. The alias arm fell through to
`IntToTypeKind(AliasTk[])`, which for an enum is `tyInteger`, and
`OrdinalTypeBound` answered about Integer and returned True before the enum arm
below was ever reached — so `for d := Low(TD) to High(TD)` ran four billion
times where the identical loop over `D` runs four.

Fixed in BOTH twins (`TryConstHighLowValue` and `TryFoldHighLowType`), whose own
comment already says *"these two are one concept in two places, so they change
together"*. Neither got a second enum arm: the alias resolves the id and lets
the existing arm answer, so the identity that makes `WriteLn` print `mon` cannot
drift between the two spellings.

## The ticket's own suggested control is in the test

A NAMED subrange OF an enum (`type TWork = tue..thu`) takes the `AliasIsSub`
arm, and the INLINE spelling of the same subrange printed member names all
along. That asymmetry is what puts the defect at the alias boundary rather than
in the formatter, and it is a row.

## Found while fixing, filed rather than folded

`Low(a)` / `High(a)` on an enum VARIABLE print `0 2` where fpc prints
`mon wed` — and the DIRECT enum variable is equally wrong, so it is not an alias
defect and does not belong here.
[[bug-p-low-and-high-of-an-enum-variable-print-the-ordinal]].
