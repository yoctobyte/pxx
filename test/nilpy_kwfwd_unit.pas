unit nilpy_kwfwd_unit;
{$MODE PXX}
{ Used by test_nilpy_double_star_into_a_pascal_method_with_a_string_default:
  a Pascal method whose parameters are typed and defaulted, the shape of
  lib/pcl/tkinter.pas's widget constructors. }
interface
uses pylib;
type
  K = class
  public
    constructor Create(a: Integer = -1; const s: AnsiString = 'dflt'; b: Integer = -1);
    procedure m(const s: AnsiString = ''; n: Integer = 7; const t: AnsiString = 't');
  end;
implementation
constructor K.Create(a: Integer; const s: AnsiString; b: Integer);
begin
  WriteLn('K ', a, ' [', s, '] ', b);
end;
procedure K.m(const s: AnsiString; n: Integer; const t: AnsiString);
begin
  WriteLn('m [', s, '] ', n, ' [', t, ']');
end;
end.
