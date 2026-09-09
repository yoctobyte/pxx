---
track: P
prio: 50
type: bug
blocked-by: []
status: open
owner: unassigned
found-by: frankD
created: 2026-09-09
summary: "Inside a `record helper for` a DYNAMIC ARRAY type, `Self` types as Integer: `Result := Length(Self)` is refused with `Length needs a string, an array or a PChar, not Integer`, and the call site `a.Cnt` separately answers `an array variable has no members (use SetLength / index it)`. A helper for a STRING type in the SAME FILE compiles and runs, which is the control that says type-helpers work and the ARRAY element of the family is the gap. fpc 3.2.2 prints `arr=3 str=4`. MEASURED CORPUS COST: this is the wall behind the Boolean16 one -- all TWELVE `tthlp*` files in the fpc-testsuite corpus stop here now, at `uthlp.pp:242`, and none of them compiles. Two faces and they may be one cause or two: the helper BODY mistyping Self, and the CALL SITE refusing member access on an array variable. Do not assume one fix clears both -- check the second after fixing the first."
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
