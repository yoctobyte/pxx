program test_call_result_as_open_array_argument;
{ A dyn-array-valued EXPRESSION -- a function result, a Copy(), a nested pair of
  both -- is a legal argument to an `array of T` parameter, exactly as a dyn-array
  VARIABLE is, for every element kind.

  Two separate defects met here. Overload resolution described such an argument
  as `(Pointer)` (its handle) rather than as the element kind a dyn-array VARIABLE
  reports, so `CatS(MkS)` came back "no overload matches". And the float rows
  went further than a refusal: `const a: array of Double` records the ELEMENT
  kind in the parameter's TypeKind, so the "integer argument to a float
  parameter" coercion fired on the dyn-array HANDLE, ran it through cvtsi2sd
  and handed the callee a float where a pointer belonged -- SumD(MkD) SEGFAULTED
  while SumD(dd) on a variable was fine, because only the call form reached it.

  Every expected line is fpc 3.2.2's own output. }
type
  TIA = array of Integer;
  TDA = array of Double;
  TSA = array of AnsiString;
  TBA = array of Boolean;
  TCA = array of Char;
  TI64 = array of Int64;
  TRec = record a: Integer; end;
  TRA = array of TRec;

function SumI(const a: array of Integer): Int64;
var i: Integer; begin Result := 0; for i := 0 to High(a) do Result := Result + a[i]; end;
function SumD(const a: array of Double): Double;
var i: Integer; begin Result := 0; for i := 0 to High(a) do Result := Result + a[i]; end;
function CatS(const a: array of AnsiString): AnsiString;
var i: Integer; begin Result := ''; for i := 0 to High(a) do Result := Result + a[i]; end;
function CntB(const a: array of Boolean): Integer;
var i: Integer; begin Result := 0; for i := 0 to High(a) do if a[i] then Inc(Result); end;
function SumR(const a: array of TRec): Integer;
var i: Integer; begin Result := 0; for i := 0 to High(a) do Result := Result + a[i].a; end;
function CatC(const a: array of Char): AnsiString;
var i: Integer; begin Result := ''; for i := 0 to High(a) do Result := Result + a[i]; end;
function SumI64(a: array of Int64): Int64;
var i: Integer; begin Result := 0; for i := 0 to High(a) do Result := Result + a[i]; end;
function LenD(const a: array of Double): Integer; begin Result := Length(a); end;

function MkI: TIA; begin SetLength(Result, 3); Result[0]:=1; Result[1]:=2; Result[2]:=3; end;
function MkD: TDA; begin SetLength(Result, 2); Result[0]:=1.5; Result[1]:=2.5; end;
function MkD0: TDA; begin SetLength(Result, 0); end;
function MkS: TSA; begin SetLength(Result, 2); Result[0]:='ab'; Result[1]:='cd'; end;
function MkB: TBA; begin SetLength(Result, 3); Result[0]:=True; Result[1]:=False; Result[2]:=True; end;
function MkR: TRA; begin SetLength(Result, 2); Result[0].a:=4; Result[1].a:=5; end;
function MkC: TCA; begin SetLength(Result, 3); Result[0]:='x'; Result[1]:='y'; Result[2]:='z'; end;
function MkI64: TI64; begin SetLength(Result, 2); Result[0]:=1000000000000; Result[1]:=7; end;

var dy: TIA; dd: TDA; ds: TSA; db: TBA; dr: TRA;
    st: array[0..2] of Double;
begin
  dy := MkI; dd := MkD; ds := MkS; db := MkB; dr := MkR;
  st[0] := 1.0; st[1] := 2.0; st[2] := 3.0;
  WriteLn('var int   : ', SumI(dy));
  WriteLn('call int  : ', SumI(MkI));
  WriteLn('copy int  : ', SumI(Copy(dy, 1, 2)));
  WriteLn('call dbl  : ', SumD(MkD):0:2);
  WriteLn('copy dbl  : ', SumD(Copy(dd, 0, 2)):0:2);
  WriteLn('call str  : ', CatS(MkS));
  WriteLn('copy str  : ', CatS(Copy(ds, 0, 2)));
  WriteLn('call bool : ', CntB(MkB));
  WriteLn('copy bool : ', CntB(Copy(db, 0, 3)));
  WriteLn('call rec  : ', SumR(MkR));
  WriteLn('copy rec  : ', SumR(Copy(dr, 0, 2)));
  WriteLn('copy call : ', SumI(Copy(MkI, 1, 2)));
  WriteLn('char      : ', CatC(MkC));
  WriteLn('int64     : ', SumI64(MkI64));
  WriteLn('len call  : ', LenD(MkD));
  WriteLn('len empty : ', LenD(MkD0));
  WriteLn('nested    : ', SumD(Copy(MkD, 0, 2)):0:2);
  WriteLn('static    : ', SumD(st):0:2);
  WriteLn('literal   : ', SumD([1.5, 2.5]):0:2);
  WriteLn('mixed lit : ', SumD([1, 2.5]):0:2);
  WriteLn('twice     : ', SumD(MkD) + SumD(MkD):0:2);
  WriteLn('inner     : ', SumI(MkI) + LenD(MkD));
end.
