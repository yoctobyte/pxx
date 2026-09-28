unit cbproc;
{ Procedural slots of every result shape a NilPy def can be thunked into, for
  test_nilpy_a_def_into_a_procedure_slot_is_called.npy. `Acc` is a unit
  global on purpose: a def named `acc` beside it must still be the def. }
{$mode objfpc}{$H+}
interface
type
  TFnI = function(a: Integer): Integer;
  TFnI2 = function(a, b: Integer): Integer;
  TPrI = procedure(a: Integer);
  TFnD = function(a: Double): Double;
  TFnS = function(a: Integer): AnsiString;
  TFn0 = function: Integer;
  TFnB = function(a: Integer): Boolean;
var Acc: Integer;
function CallI(f: TFnI; v: Integer): Integer;
function CallI2(f: TFnI2; a, b: Integer): Integer;
function CallPr(f: TPrI; v: Integer): Integer;
function CallD(f: TFnD; v: Double): Double;
function CallS(f: TFnS; v: Integer): AnsiString;
function Call0(f: TFn0): Integer;
function CountIf(f: TFnB; n: Integer): Integer;
implementation
function CallI(f: TFnI; v: Integer): Integer; begin Result := f(v) + f(v + 1); end;
function CallI2(f: TFnI2; a, b: Integer): Integer; begin Result := f(a, b) * 2; end;
function CallPr(f: TPrI; v: Integer): Integer; begin Acc := 0; f(v); f(v * 2); Result := Acc; end;
function CallD(f: TFnD; v: Double): Double; begin Result := f(v) + 0.25; end;
function CallS(f: TFnS; v: Integer): AnsiString; begin Result := f(v) + '|' + f(v + 1); end;
function Call0(f: TFn0): Integer; begin Result := f() + f(); end;
function CountIf(f: TFnB; n: Integer): Integer; var i: Integer;
begin Result := 0; for i := 1 to n do if f(i) then Inc(Result); end;
end.
