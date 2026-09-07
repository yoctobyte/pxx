program test_an_overload_report_spells_an_array_argument_the_same_at_a_method_call;
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
type
  TR = record N: Integer; end;
  TArrR = array of TR;
  TCls = class F: Integer; end;
  TC = class
    procedure Q(a: Integer; c: TCls; r: TArrR); overload;
    procedure Q(a: Integer; c: TCls; r: string); overload;
    procedure Go;
  end;

procedure TC.Q(a: Integer; c: TCls; r: TArrR); begin if a = 0 then WriteLn(Length(r)); end;
procedure TC.Q(a: Integer; c: TCls; r: string); begin if a = 0 then WriteLn(r); end;

procedure TC.Go;
var ar: TArrR; n: Integer;
begin
  SetLength(ar, 1); n := 1;
  Q(n, n, ar);          { second argument is an Integer, not a TCls }
end;

var o: TC;
begin
  o := TC.Create;
  o.Go;
end.
