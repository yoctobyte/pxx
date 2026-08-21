{ SPDX-License-Identifier: MPL-2.0 }
unit pxxdial;
{$MODE PXX}   { our dialect — exactly what all 136 lib/rtl units now declare }
{ A unit whose only job is to carry a {$MODE PXX} directive across a `uses`
  boundary. See test/test_mode_delphi_unit_leak.pas.
  bug-a-a-units-mode-directive-turns-delphi-mode-off-for-the-program }
interface
function PxxDialAnswer: Integer;
implementation
function PxxDialAnswer: Integer;
begin
  PxxDialAnswer := 42;
end;
end.
