{ SPDX-License-Identifier: MPL-2.0 }
unit delphidial;
{$mode delphi}
{ The OTHER arm: a unit that turns delphi mode ON. It must not leak either —
  the includer's dialect is the includer's business, in both directions.
  See test/test_mode_delphi_unit_leak_off_fail.pas.
  bug-a-a-units-mode-directive-turns-delphi-mode-off-for-the-program }
interface
function DelphiDialAnswer: Integer;
implementation
function DelphiDialAnswer: Integer;
begin
  Result := 7;
end;
end.
