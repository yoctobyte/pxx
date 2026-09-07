program test_an_overload_report_spells_an_array_argument_the_same_at_a_free_call;
{$mode objfpc}
{ NEGATIVE fixture: it must NOT compile. What is asserted is the DIAGNOSTIC.

  The two halves of an overload report -- the argument list and the candidate
  list -- are produced by different code, and `argTypes[j]` carries the ELEMENT
  kind of an array argument exactly as Params[j].TypeKind does for an array
  parameter. So one report spelled the same array `record` on one side and
  `array of record` on the other, which reads as a mismatched argument where
  there is none: argument 3 MATCHES, only argument 2 is wrong.

  TWO FILES because the two call shapes print through DIFFERENT printers -- the
  free call appends the shared OverloadReport (symtab.inc), the method probe
  builds its own string (pasparser_call.inc) -- and because the METHOD half
  halts rather than recovering, so it cannot share a compile with the free one.
  Fixing one printer and closing the ticket is how the halves came to disagree.

  bug-p-the-two-halves-of-an-overload-report-spell-an-array-argument-differently }

{ THE FREE HALF ALSO CARRIES THE ROOT CAUSE, and it is not the spelling.
  `P`'s third parameter is an open array whose element is a RECORD, which is
  what ParamIsVarRecArrayAt answers `array of const` to -- so the variadic
  bracket-elision fallback fires on this call, splices an AN_VARREC_ARRAY in
  place of `ar`, re-resolves, fails, and leaves OverloadReport describing the
  list IT invented. The report was correct about a different argument list.
  Keep the parameter a record-element array: with any other element type the
  fallback never runs and this fixture asserts only the spelling. }

type
  TR = record N: Integer; end;
  TArrR = array of TR;
  TCls = class F: Integer; end;

procedure P(a: Integer; c: TCls; r: TArrR); begin if a = 0 then WriteLn(Length(r)); end;

var ar: TArrR; n: Integer;
begin
  SetLength(ar, 1); n := 1;
  P(n, n, ar);          { second argument is an Integer, not a TCls }
end.
