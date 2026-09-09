---
track: P
prio: 50
type: bug
blocked-by: []
status: done
owner: frankZ
found-by: frankD
created: 2026-09-09
summary: "FIXED 2026-09-09. A `record helper for` an ARRAY type: `Self` typed as Integer in the body (`Length needs a string, an array or a PChar, not Integer`) and the call site separately refused the member (`an array variable has no members`). The ticket asked whether that is one cause or two -- it is ONE CAUSE WITH THREE CONSUMERS: there is no `tyArray` in `TTypeKind` at all, so a helper target was representable as a scalar kind (`UClsHelperTk`) or a record id (`UClsHelperRec`) and an array is NEITHER; `ParseTypeKind` answered its unknown-name default and the decl side, the impl side and the call-site guard each read that default independently. Fixed by a third carrier, `UClsHelperArrAi`, keyed on the ArrType ROW. TWO CORRECTIONS TO THIS TICKET AS FILED: the defect is not specific to DYNAMIC arrays -- `array[0..3] of T` failed identically and both are fixed; and the corpus claim has moved -- `uthlp.pp:242` is cleared for all TWELVE `tthlp*` files, four of which (5, 6, 7, 8) now compile outright, while eight stop at eight further distinct walls, none of them this one. Repro now prints `arr=3 str=4`, matching fpc 3.2.2."
---

# `Self` in a record helper for a dynamic array types as Integer

Found 2026-09-09 (frankD) behind
[[feature-p-the-booleannn-family-of-explicit-width-boolean-type-names]] — it was
invisible until `Boolean16` resolved, because `uthlp.pp` declares its helpers in
name order and the boolean one refused first.

## Repro — 24 lines, and it carries its own control

```pascal
program hlp;
{$mode delphi}{$H+}{$modeswitch typehelpers}
type
  TArr = array of LongInt;
  TStr = AnsiString;
  TArrHelper = record helper for TArr
    function Cnt: LongInt;
  end;
  TStrHelper = record helper for TStr
    function Cnt: LongInt;
  end;
function TArrHelper.Cnt: LongInt;
begin
  Result := Length(Self);      { <- pxx: Length needs ... not Integer }
end;
function TStrHelper.Cnt: LongInt;
begin
  Result := Length(Self);      { <- compiles: the control }
end;
var a: TArr; s: TStr;
begin
  SetLength(a, 3); s := 'abcd';
  WriteLn('arr=', a.Cnt, ' str=', s.Cnt);   { <- pxx: an array variable has no members }
end.
```

```
fpc 3.2.2:  arr=3 str=4
pxx (9b2cfef2721d):
  hlp.pas:14: error: Length needs a string, an array or a PChar, not Integer
  hlp.pas:23: error: an array variable has no members (use SetLength / index it)
```

**The string helper is in the same file, same modeswitch, same body, and it
compiles.** So this is not "type helpers are unimplemented" — it is the ARRAY
member of the family, and the control is what makes that claim rather than a
guess. The mode line matters: `record helper for` a non-record needs
`{$modeswitch typehelpers}`, and in `{$mode objfpc}` fpc refuses the spelling
outright (`":" expected but "FOR" found`), so a reduction written in objfpc
measures the wrong thing.

## Two faces, possibly two causes

1. **The BODY.** `Self` inside `TArrHelper.Cnt` is typed Integer rather than
   `TArr`. Integer is suspicious in its own right — a dynamic array handle is
   pointer-width, so this looks like the helper's `Self` falling into a default
   rather than being given the helped type at all.
2. **The CALL SITE.** `a.Cnt` on an array variable is refused by a message that
   predates helpers (`use SetLength / index it`) — a member-access guard that
   does not know a helper can put members on an array.

They may be one cause, and the second error may be a cascade of the first.
**They may also not be.** The call-site message comes from a different guard
than the body's type, so fixing `Self` need not open member access.
[[a-reduction-can-drift-onto-a-neighbouring-defect]] — check the second after
the first, and do not close on the repro going green without re-running the
corpus row.

## A CHECKED NEGATIVE, so nobody spends a lead on it

**This is NOT the same site as
[[bug-p-a-string-literal-bound-to-a-pwidechar-is-emitted-narrow]]'s `Length`
defect, and the two `Length` symptoms are a coincidence of the builtin's name.**
Measured by frankS 2026-09-09: `IsNodePChar` (`ir.inc:4020`) exits on its third
line unless the node is `tyPointer`, so a dynamic-array `Self` never reaches it
at all. And per this ticket's own title the defect is `Self` typing as Integer —
the RECEIVER's type — not `Length`'s dispatch.

So a `PWideCharToString` fixes nothing here, and fixing this fixes nothing
there. Two tickets, two sites, one builtin name in both error messages.

## Corpus

`library_candidates/fpc-testsuite/tests/test/uthlp.pp:242`, `Result :=
Length(Self)` in `TTestArrayHelper`, a `record helper for TTestArray = array of
LongInt`. All twelve `tthlp*` files that use `uthlp` stop here:
`tthlp3 4 5 6 7 8 14 18 19 26a 26b 26c`. Before 2026-09-09 all twelve stopped
one declaration earlier on `unknown type: Boolean16`; **the wall moved and the
file count did not** — none of the twelve compiles yet, and reporting them as
unblocked would be wrong.

Behind THIS one there is at least one more: `tthlp3` also reports `"Test": this
value is still a POINTER here` at its own line 89, which is a third wall in the
same stack and is not characterised.


## Resolution (2026-09-09, frankZ) — one cause, three consumers

The ticket's own question was "one cause or two, and do not assume one fix
clears both". **One cause, and it clears three things rather than two.**

**There is no `tyArray` in `TTypeKind`.** Arrays are not a kind at all here —
they live in a separate `ArrType` table (`ArrTypeElemTk`, `ArrTypeIsDyn`,
`ArrTypeDynDepth`, `ArrTypeNDims`, `ArrTypeLo/Hi`), reached by name through
`FindArrayType`. A helper's target was carried in exactly two slots, `Ord(kind)`
and a record id, and **an array is neither**, so `ParseTypeKind('TArr')` fell to
its unknown-name default and every consumer read that default:

1. `ParseRecordMethodDecl` typed the declared `Self` from it.
2. `ParseProcOrFunc` typed the implemented `Self` from it — the same wrong
   answer, which is *why the impl still bound*: both sides agreed, on a lie.
3. `pasparser_lval.inc` never consulted the helper tables for an array receiver
   at all; it excluded arrays outright, one guard earlier.

So the two faces the ticket saw were the same missing fact read at three points.
The body's error and the call site's error were never a cascade — they were
siblings.

### The fix

`UClsHelperArrAi[ci]` — the helper target's ArrType row **plus one**, 0 meaning
"not an array" — written by `NoteHelperArrayTarget` at the two reachable
`helper for` sites, from the target's NAME captured before `ParseTypeKind`
consumes it. The `class helper for` site is deliberately not a caller: it
refuses any non-class target, so an array cannot reach it, and a call there
would be a branch that cannot fire.

`SymArrAi[idx]` is the receiver-side twin: the ArrType row a *variable* was
declared through. **A symbol otherwise records an array's SHAPE and not its
IDENTITY**, and shape is the wrong key — `TA = array of LongInt` and
`TB = array of LongInt` are indistinguishable by element kind, dyn-ness and
depth, and a helper for `TA` must not attach to a `TB`. That is asserted:
`test/test_a_record_helper_for_one_array_type_does_not_attach_to_another_fail.pas`
is `%FAIL`, and **the shape-matching implementation compiles it while passing
every other array-helper row in the tree**.

### Correction 1 — it was never about DYNAMIC arrays

The ticket, its slug and its repro all say dynamic. A `record helper for
array[0..3] of LongInt` failed with the identical message for the identical
reason; `ParseTypeKind` cannot see either. Both are fixed and both are asserted
(`fixed=4` beside `dyn=3` in `test/test_record_helper_for_an_array.pas`). The
slug is left alone — renaming it would break citations — but nobody should read
"dynamic" as a boundary.

### Correction 2 — the corpus claim has moved

Filed as: all twelve `tthlp*` files that use `uthlp` stop at `uthlp.pp:242`.
Now: **zero do** — `grep -l 'uthlp.pp:242'` over all twelve logs returns
nothing. Four compile outright (`tthlp5 6 7 8`). The other eight stop at eight
*different* walls, and listing them is the point, because "still fails" would
otherwise read as "this fix did not work":

| file | now stops at |
| --- | --- |
| `tthlp3` | `:89` `"Test": this value is still a POINTER here` — **the third wall this ticket predicted**, now confirmed and still uncharacterised |
| `tthlp4` | `:48` `expected comma or close parenthesis` |
| `tthlp14` | `:71` `expected '(' before '.'` |
| `tthlp18` | `:13` `no overload of Create matches these arguments` |
| `tthlp19` | `:11` `expected 'begin' before '.'` |
| `tthlp26a/b/c` | `:12`/`:13` `expected '(' before '.'` |

`tthlp14` and `tthlp26a/b/c` share one message on a **type-name receiver**
(`String.TestClass`), which is plausibly the same family as the open class-helper
dispatch work — noted rather than claimed; nobody has reduced them.

### Six controls, all measured

`arr=3 str=4` matching fpc 3.2.2 is the headline. Beside it: no-helper array
still refused; a helper for `TA` does not attach to a same-shape `TB`; `TA` gets
it (7); fixed array (4); by-ref mutation through `Self` survives (20 in the
probe, `sum=15` in the committed test — `Self` is by reference, so a helper that
writes actually writes); string helper unchanged (8).

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit ba4294885.
