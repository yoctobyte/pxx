{ SPDX-License-Identifier: MPL-2.0 }
program test_a_program_routine_shadows_a_system_const;
{ A routine the PROGRAM declares shadows a predefined System const of the same
  name, as it does in fpc. `function MaxInt(A, B)` was refused as "a CONST
  and cannot be called" at HEAD, and pin v421 compiled it into a SEGFAULT.
  docs/language/generics.md reaches the same shape via
  `specialize Max<Integer> as MaxInt`. The SAME-unit const/routine pair stays
  refused: test_const_shadows_routine_fail. }
function MaxInt(A, B: Integer): Integer;
begin
  if A < B then Result := B else Result := A;
end;
procedure MaxSmallInt(x: Integer);
begin
  writeln('proc ', x);
end;
begin
  writeln('Max of 10 and 20: ', MaxInt(10, 20));
  MaxSmallInt(5);
  writeln('MaxLongInt ', MaxLongInt);
end.
