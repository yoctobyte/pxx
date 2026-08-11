program TestOverloadArrayVsScalar;
{ Regression for bug-a-an-integer-argument-binds-a-fixed-array-overload.

  A fixed-array parameter's Params[].TypeKind is its ELEMENT kind, so to the
  overload matcher `const a: TArr` and `x: Integer` presented the SAME signature
  and the array one won on declaration order. `Sum(7)` was then refused by the
  by-ref check ("by-reference argument must be a variable" — a diagnostic naming
  the symptom, one step past the cause), and the far worse `Sum(n)` compiled:
  an lvalue satisfies the by-ref check, so the callee read three array elements
  off a 4-byte Integer and SEGFAULTED.

  The array argument must still win the array overload — including a
  fixed-array-returning CALL, whose element kind is the same tyInteger. }
type
  TArr = array[0..2] of Integer;

function MkArr: TArr;
begin MkArr[0] := 1; MkArr[1] := 2; MkArr[2] := 3; end;

function Sum(const a: TArr): Integer; overload;
begin Sum := a[0] + a[1] + a[2]; end;
function Sum(x: Integer): Integer; overload;
begin Sum := x * 10; end;
function Sum(x: Double): Integer; overload;
begin Sum := Trunc(x) + 1000; end;

{ open arrays and `array of const` must be unaffected: the first legitimately
  takes an array of any length, the second legitimately takes anything }
function Pick(const a: array of Integer): Integer; overload;
begin Pick := 100 + Length(a); end;
function Pick(x: Integer): Integer; overload;
begin Pick := x; end;

var
  v: TArr;
  d: array of Integer;
  n: Integer;
begin
  v[0] := 1; v[1] := 2; v[2] := 3;
  SetLength(d, 2); d[0] := 7; d[1] := 8;
  n := 5;

  WriteLn('arr    ', Sum(v));         { 6   }
  WriteLn('call   ', Sum(MkArr));     { 6   }
  WriteLn('var    ', Sum(n));         { 50  — segfaulted }
  WriteLn('lit    ', Sum(7));         { 70  — was refused }
  WriteLn('float  ', Sum(2.5));       { 1002 }

  WriteLn('open a ', Pick(v));        { 103 }
  WriteLn('open d ', Pick(d));        { 102 }
  WriteLn('open c ', Pick([1, 2, 3]));{ 103 }
  WriteLn('open i ', Pick(9));        { 9   }
  WriteLn('OVERLOAD ARRAY VS SCALAR OK');
end.
