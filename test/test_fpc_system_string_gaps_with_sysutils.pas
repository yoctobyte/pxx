{ The same rows as test_fpc_system_string_gaps.pas with SysUtils in scope:
  its Copy/Pos/UpCase overloads shadow the intrinsics, so each needs the
  missing form too. Power: float-only, as in FPC (Power(2, -1) is 0.5). }
program test_fpc_system_string_gaps_with_sysutils;
{$mode objfpc}{$H+}
uses SysUtils, StrUtils, Math;
var s: AnsiString;
begin
  s := 'hello world';
  WriteLn('[', Copy(s, 7), '][', Copy(s, 20), '][', Copy(s, 0), ']');
  WriteLn(Pos('o', s, 6), ' ', Pos('o', s, 9), ' ', Pos('o', s, 1), ' ', Pos('o', s, 0), ' ', Pos('o', s, 50), ' ', Pos('', s, 2), ' ', Pos('ld', s, 10), ' ', Pos('o', s));
  WriteLn(UpCase(s), ' ', UpCase('x'), ' ', UpCase('mIx3d_z'), ' [', UpCase(''), ']');
  WriteLn('[', Space(3), '][', Space(0), '] ', Length(Space(-2)), ' ', Length(Space(300)));
  WriteLn(Power(2, 10):0:3, ' ', Power(2.5, 2):0:4, ' ', Power(9, 0.5):0:4, ' ', Power(2, -1):0:4);
end.
