program test_a_program_declaring_its_own_tarray_shadows_the_ambient_one;
{ The shadow control for test_tarray_is_ambient_with_no_uses_clause: naming
  TArray pulls compiler/builtin/sysgenerics.pas in, and a program that then
  declares a plain (non-generic) TArray of its own must still get ITS type. }
{$mode objfpc}
type
  TArray = array of LongInt;
var
  r: TArray;
begin
  SetLength(r, 2); r[0] := 4;
  WriteLn('1 ', Length(r), ' ', r[0]);
end.
