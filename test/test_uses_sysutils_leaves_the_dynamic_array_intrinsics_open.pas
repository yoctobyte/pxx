program test_uses_sysutils_leaves_the_dynamic_array_intrinsics_open;
{$MODE OBJFPC}{$H+}

{ `uses sysutils` must not take Delete/Insert away from a dynamic array.

  It did, for as long as lib/rtl/sysutils.pas declared the string overloads:
  SoftIntrinsicOpen is a Boolean asked BEFORE any argument is parsed, so a
  same-named routine in scope closes the intrinsic for every argument shape,
  including ones it could never bind. `Delete(a, 1, 2)` answered `no overload
  of Delete matches these arguments` and offered the string overload as the
  only candidate. fpc compiles it -- fpc keeps both in `system`, not sysutils.

  BOTH SPELLINGS ARE IN ONE FILE ON PURPOSE. The string rows and the array rows
  have to pass in the SAME compilation: the defect was one declaration taking
  the array shape away while the string shape kept working, so a file that
  tests only one of them passes in both worlds. The string rows are the half
  that must not regress, and they are what a careless fix would break.

  Expectations are fpc's own output. bug-p-one-uses-sysutils-removes-dynamic-
  array-delete-and-insert }

uses sysutils;

var
  a: array of Integer;
  s: AnsiString;
  i: Integer;

procedure ShowArr;
var k: Integer;
begin
  for k := 0 to High(a) do Write(a[k], ' ');
  WriteLn;
end;

begin
  { the array shape -- the half that could not compile at all }
  SetLength(a, 5);
  for i := 0 to 4 do a[i] := i;
  Delete(a, 1, 2);
  ShowArr;
  Insert(99, a, 1);
  ShowArr;
  Insert(77, a, 0);
  ShowArr;
  Delete(a, 0, 1);
  ShowArr;

  { the string shape, through the intrinsic now, including the edges where a
    clamp is the whole behaviour }
  s := 'hello world'; Delete(s, 1, 6);   WriteLn('[', s, ']');
  s := 'hello world'; Delete(s, 6, 100); WriteLn('[', s, ']');
  s := 'hello world'; Delete(s, 0, 3);   WriteLn('[', s, ']');
  s := 'hello world'; Delete(s, 20, 3);  WriteLn('[', s, ']');
  s := 'hello world'; Delete(s, 3, 0);   WriteLn('[', s, ']');
  s := 'abc'; Insert('XY', s, 1);  WriteLn('[', s, ']');
  s := 'abc'; Insert('XY', s, 4);  WriteLn('[', s, ']');
  s := 'abc'; Insert('XY', s, 99); WriteLn('[', s, ']');
  s := 'abc'; Insert('XY', s, 0);  WriteLn('[', s, ']');
  s := 'abc'; Insert('', s, 2);    WriteLn('[', s, ']');
  WriteLn('SYSUTILSINTRINSICS OK');
end.
