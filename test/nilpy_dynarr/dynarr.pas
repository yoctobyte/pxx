unit dynarr;
{$mode objfpc}
{ Pascal `array of T` results called from NilPy. See
  test_nilpy_a_pascal_dynamic_array_result_indexes_directly.npy. }
interface
type
  TIntArr = array of Integer;
  TStrs = array of AnsiString;
  TBytes2 = array of Byte;
  TDbl = array of Double;
function MakeArr(n: Integer): TIntArr;
function MkStrs(n: Integer): TStrs;
function MkBytes(n: Integer): TBytes2;
function MkDbl(n: Integer): TDbl;
function SumV(a: TIntArr): Integer;
function SumO(a: array of Integer): Integer;
function SumC(const a: TIntArr): Integer;
implementation
function MakeArr(n: Integer): TIntArr; var i: Integer; begin SetLength(Result, n); for i := 0 to n - 1 do Result[i] := i * 10; end;
function MkStrs(n: Integer): TStrs; var i: Integer; begin SetLength(Result, n); for i := 0 to n - 1 do Result[i] := Chr(65 + i); end;
function MkBytes(n: Integer): TBytes2; var i: Integer; begin SetLength(Result, n); for i := 0 to n - 1 do Result[i] := i + 1; end;
function MkDbl(n: Integer): TDbl; var i: Integer; begin SetLength(Result, n); for i := 0 to n - 1 do Result[i] := i + 0.5; end;
function SumV(a: TIntArr): Integer; var i: Integer; begin Result := 0; for i := 0 to High(a) do Result := Result + a[i]; end;
function SumO(a: array of Integer): Integer; var i: Integer; begin Result := 0; for i := 0 to High(a) do Result := Result + a[i]; end;
function SumC(const a: TIntArr): Integer; var i: Integer; begin Result := 0; for i := 0 to High(a) do Result := Result + a[i]; end;
end.
