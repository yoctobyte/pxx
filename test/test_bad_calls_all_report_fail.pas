program test_bad_calls_all_report_fail;
{ A call whose arguments match no overload is a SEMANTIC failure over a
  well-formed token stream: the arguments and the closing paren are already
  consumed when the mismatch is found, so the parser is exactly where a good
  call would have left it. That is what makes it safe to report and carry on,
  and it is the same reasoning the unresolved-name slices used.
  feature-a-error-does-not-halt-so-a-parse-can-be-speculative

  fpc 3.2.2 reports all four of the bad calls below, on lines 30, 31, 32 and 33.
  pxx reported line 30 and stopped, so a user fixing four bad calls paid four
  compile cycles.

  Line 33 is the row that needed the second, separate recovery: the bad call is
  inside an EXPRESSION, where an empty statement is not an available stand-in —
  it needs a VALUE. Without the poison Integer the expression around it would
  produce a second, meaningless diagnostic about the operand it never got.

  `Two(1, 2)` at the end must NOT be reported: recovery that also flags correct
  code is worse than halting. And no binary may be written — the driver halts on
  ErrCount > 0 before RTTI, fixups or any emission, so nothing poisoned can
  reach codegen.

  This program is EXPECTED TO FAIL to compile; the Makefile asserts the exact
  shape of the failure. }
{$mode objfpc}{$H+}
procedure Two(x, y: Integer); begin end;
function  F(x: Integer): Integer; begin Result := x; end;
var i: Integer;
begin
  Two(1);                { too few  — statement position }
  Two(1, 2, 3);          { too many — statement position }
  i := F(1, 2);          { too many — expression position }
  i := F(1) + F(2, 3);   { the bad call is an OPERAND }
  Two(1, 2);             { correct — must stay silent }
  WriteLn(i);
end.
