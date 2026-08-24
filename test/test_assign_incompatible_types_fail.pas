{ %FAIL-style negative: an assignment between incompatible types.

  Seventeen of the eighteen assignments fpc 3.2.2 rejects with `Incompatible
  types` used to compile clean here, in every direction. Two of them are the
  argument for checking at all, because they are not laxness, they are a wrong
  answer with no diagnostic at any stage:

    s := 'hello';  i := s;  WriteLn(i);   { printed the string HANDLE }
    i := 7;        s := i;  WriteLn(s);   { SEGFAULT: 7 read as a handle }

  Those two lines are kept in the ticket even now that they stop compiling —
  they are what makes the case, and a test that only says "rejected" loses it.

  Every line below is one row of that table. They are all in ONE program on
  purpose: the check reports and CARRIES ON, so the test asserts twelve
  diagnostics from a single compile, which is also what proves the recovery
  works. The Makefile row greps for the count.

  DELIBERATELY ABSENT, and they must stay absent: `i := d`, `b := i`, `i := b`,
  `p := i`, `i := p`. fpc rejects those too, but each has a defined meaning in
  this dialect (truncation, an ordinal round-trip, a systems-language
  pointer/integer conversion) — they belong behind the proposed --strict-assign
  flag, not in the default. Adding them here would freeze a decision this
  ticket deliberately did not take.
  bug-p-an-assignment-is-not-type-checked-at-all }
program test_assign_incompatible_types_fail;
{$mode objfpc}{$H+}
type TRec = record a: Integer; b: AnsiString; end;
     TCls = class x: Integer; end;
var r: TRec; c: TCls; i: Integer; s: AnsiString;
    d: Double; b: Boolean; ch: Char; u: UCS4Char;
begin
  i := s;      { 1  a managed handle read as a number }
  s := i;      { 2  a number dereferenced as a handle — the segfault }
  i := r;      { 3 }
  r := i;      { 4 }
  i := c;      { 5 }
  c := i;      { 6 }
  i := 'text'; { 7  a literal, not a variable — the RHS shape matters }
  b := s;      { 8 }
  s := b;      { 9 }
  d := s;      { 10 }
  ch := s;     { 11 a string is never a legal source for a Char... }
  s := r;      { 12 }
  s := u;      { 13 UCS4Char is LongWord in disguise; pinned SEGFAULTED here }
  s := ch;     { ...though a Char IS a legal source for a string: SILENT }
  d := i;      { and a numeric widening is legal: SILENT }
end.
