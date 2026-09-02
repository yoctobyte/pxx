program test_setlength_cast_refusal;
{ The control for the SetLength rows in test_alias_cast_assign_target.pas, and
  it has to be its own file because the thing asserted is a COMPILE-TIME
  REFUSAL.

  `SetLength(TS(s), n)` drops a cast to a STRING type, because such a cast is a
  value-level no-op and there is nothing a resize can reinterpret. That drop is
  scoped to string types on purpose: an INT alias cast is not a no-op, FPC
  refuses it (`Type mismatch`), and a drop that ran on every cast would quietly
  resize the integer's storage instead.

  Without this row the scope is unasserted, and a later widening to "any
  non-pointer alias" would pass every green row in the sibling file. That exact
  widening was tried once already, in 850a9e4cd, and it broke a shape nobody was
  watching.

  The recipe greps for the diagnostic rather than just asserting a nonzero exit:
  a file can fail to compile for a hundred reasons and only one of them is this
  one. }
type TI = Integer;
var i: Integer;
begin
  i := 0;
  SetLength(TI(i), 5);
  WriteLn(i);
end.
