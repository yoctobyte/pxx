{ SPDX-License-Identifier: MPL-2.0 }
unit test_nilpy_define_unit;
{ The PXX_NILPY define (compiler.pas, beside PXX_NILPY_STR) as a unit sees it:
  a unit's Python-only half is guarded by it (lib/rtl/platform/esp/espi2c.pas),
  so the define must reach a USED UNIT, and must be absent from a Pascal build.
  Both answers come out of this one function. }
{$MODE PXX}
interface
function frontend: AnsiString;
implementation
function frontend: AnsiString;
begin
{$ifdef PXX_NILPY}
  frontend := 'nilpy';
{$else}
  frontend := 'pascal';
{$endif}
end;
end.
