{ A FRESH dyn-array call result passed to an OPEN-ARRAY parameter must be freed.

  `SumC(MkIA(i))` measured allocs=921 frees=0 — every array leaked WHOLE, not one
  element of it, for `const` and by-value parameters alike and for both managed
  and non-managed element types. An open-array param receives (data pointer,
  high), a RAW POINTER, and a dyn-array source already carries the [len][data]
  layout the param wants, so it was passed straight through with nothing
  retaining or releasing it. Same ownership family as the Copy/concat operands
  and the eight pointer seams before them.

  test_open_array_no_leak.pas does NOT cover this and is not a duplicate: it
  passes NAMED STATIC arrays (`array[0..2] of AnsiString`), which have an owner
  by construction. The leak needs a dyn-array RVALUE, which nothing in the corpus
  passed to an open array.

  THE THREE CONTROLS BELOW ARE THE POINT, because the fix is a park and a park
  that fires too eagerly double-frees. A named array, a literal `[1,2,3,4]` and
  an already-owned `Copy(...)` all measured CLEAN before the fix and must stay
  clean and correct after it — IRParkManagedDyn returns its value unchanged
  unless the value owns a fresh +1.

  Every k below is asserted against the value measured BEFORE the fix, so a park
  that silently freed something still in use shows up as a wrong sum rather than
  only as a crash.
  bug-a-a-fresh-dyn-array-result-passed-to-an-open-array-param-is-never-freed }
program test_open_array_fresh_result_leaks;
{$mode objfpc}{$H+}

var
  iv: array of Integer;
  k, i, fail: Integer;

function MkIA(kk: Integer): array of Integer;
begin
  SetLength(Result, 4);
  Result[0] := 11; Result[1] := 22; Result[2] := 33; Result[3] := 44;
end;

function MkArr(kk: Integer): array of AnsiString;
begin
  SetLength(Result, 4);
  Result[0] := 'aa'; Result[1] := 'bb'; Result[2] := 'cc'; Result[3] := 'dd';
end;

function SumC(const a: array of Integer): Integer;
var j: Integer;
begin SumC := 0; for j := 0 to High(a) do SumC := SumC + a[j]; end;

function SumV(a: array of Integer): Integer;
var j: Integer;
begin SumV := 0; for j := 0 to High(a) do SumV := SumV + a[j]; end;

function CntS(const a: array of AnsiString): Integer;
var j: Integer;
begin CntS := 0; for j := 0 to High(a) do CntS := CntS + Length(a[j]); end;

procedure Chk(const what: AnsiString; got, want: Integer);
begin
  if got <> want then
  begin WriteLn('FAIL ', what, ' = ', got, ' want ', want); Inc(fail); end;
end;

begin
  fail := 0;
  SetLength(iv, 4); iv[0] := 11; iv[1] := 22; iv[2] := 33; iv[3] := 44;

  { the leak: a fresh call result straight into an open-array param }
  k := 0; for i := 1 to 500 do k := k + SumC(MkIA(i));
  Chk('const open array, fresh integer array', k, 55000);

  k := 0; for i := 1 to 500 do k := k + SumV(MkIA(i));
  Chk('by-value open array, fresh integer array', k, 55000);

  k := 0; for i := 1 to 500 do k := k + CntS(MkArr(i));
  Chk('const open array, fresh AnsiString array', k, 4000);

  { CONTROLS — all three were clean before the fix and the park must skip them }
  k := 0; for i := 1 to 500 do k := k + SumC(iv);
  Chk('control: NAMED array', k, 55000);

  k := 0; for i := 1 to 500 do k := k + SumC([1, 2, 3, 4]);
  Chk('control: literal open array', k, 5000);

  k := 0; for i := 1 to 500 do k := k + SumC(Copy(MkIA(i)));
  Chk('control: already-owned Copy() result', k, 55000);

  WriteLn('fail=', fail);
  if fail = 0 then WriteLn('OPENARRAYFRESH OK') else WriteLn('OPENARRAYFRESH FAILED');
end.
