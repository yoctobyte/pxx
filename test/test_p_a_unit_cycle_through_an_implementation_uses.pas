{ A unit cycle closed through an IMPLEMENTATION uses clause.

  This is the standard, legal form of mutual unit recursion in Pascal and it is
  the reason `uses` is split into two clauses at all: ucycle_a's INTERFACE uses
  ucycle_b, and ucycle_b's IMPLEMENTATION uses ucycle_a. fpc 3.2.2 compiles and
  runs it; the rows below are its output.

  WHAT MAKES IT FAIL, so a later reader does not "simplify" the fixture into
  something that cannot fail: ucycle_a's declarations sit BELOW its own `uses`
  line, so at the instant ucycle_b's implementation asks for them, ucycle_a's
  interface has been parsed only as far as that line. Nothing is being hidden --
  it has not been read yet. Hoisting them above the `uses` makes every row pass
  while measuring nothing.

  THREE KINDS ARE ASKED FOR ON PURPOSE -- a var, a type and a const -- because
  they resolve through different tables, and a fix that reaches one need not
  reach the other two.
  bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface }
program test_p_a_unit_cycle_through_an_implementation_uses;

uses ucycle_a, ucycle_b;

var
  fails: LongInt;

procedure Chk(const what: AnsiString; got, want: LongInt);
begin
  if got = want then
    WriteLn(what, ' ok')
  else
  begin
    WriteLn(what, ' FAIL got=', got, ' want=', want);
    fails := fails + 1;
  end;
end;

begin
  fails := 0;
  Chk('R01 var-from-A', BCall(7), 8);
  Chk('R02 type-from-A', BUsesAType(21), 42);
  Chk('R03 const-from-A', BReadsAConst, 41);
  Chk('R04 A-calls-B', ACallsB(7), 8);
  WriteLn('fails=', fails);
  WriteLn('UCYCLE OK');
end.
