{ FPC System string routines that were missing or wrong, each row fpc 3.2.2 output:
  Copy(s, i), Pos with an offset, UpCase(string), Space. No `uses`: these are
  System intrinsics. The `uses SysUtils` twin is
  test_fpc_system_string_gaps_with_sysutils.pas. }
program test_fpc_system_string_gaps;
{$mode objfpc}{$H+}
var s: AnsiString;
begin
  s := 'hello world';
  WriteLn('[', Copy(s, 7), '][', Copy(s, 20), '][', Copy(s, 0), ']');
  WriteLn(Pos('o', s, 6), ' ', Pos('o', s, 9), ' ', Pos('o', s, 1), ' ', Pos('o', s, 0), ' ', Pos('o', s, 50), ' ', Pos('', s, 2), ' ', Pos('ld', s, 10), ' ', Pos('o', s));
  WriteLn(UpCase(s), ' ', UpCase('x'), ' ', UpCase('mIx3d_z'), ' [', UpCase(''), ']');
  WriteLn('[', Space(3), '][', Space(0), '] ', Length(Space(-2)), ' ', Length(Space(300)));
end.
