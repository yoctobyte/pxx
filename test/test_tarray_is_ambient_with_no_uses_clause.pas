program test_tarray_is_ambient_with_no_uses_clause;
{ FPC declares `TArray<T>` in its SYSTEM unit, so a program that names it needs
  no `uses` at all. pxx has no lib/rtl/system.pas and had TArray in SysUtils,
  which covers rtl-generics (whose files use SysUtils anyway) and covers NONE of
  the fpc-testsuite population (0 of 6 files naming TArray<> use SysUtils).
  compiler/builtin/sysgenerics.pas is the ambient stand-in.
  NO `uses` LINE IN THIS FILE, and that is the whole assertion. }
{$mode objfpc}
type
  TRec = record A: specialize TArray<Byte>; B: Integer; end;

function Build(a: array of LongInt): specialize TArray<LongInt>;
var i: LongInt;
begin
  SetLength(Result, Length(a));
  for i := 0 to High(a) do Result[i] := a[i] * 2;
end;

var
  r: specialize TArray<LongInt>;
  s: specialize TArray<AnsiString>;
  q: TRec;
begin
  r := Build([1, 2, 3]);                 { RESULT position }
  WriteLn('1 ', Length(r), ' ', r[0], ' ', r[2]);
  SetLength(s, 2); s[1] := 'ok';         { a second argument type }
  WriteLn('2 ', Length(s), ' ', s[1]);
  SetLength(q.A, 3); q.A[2] := 9; q.B := 7;   { RECORD FIELD position }
  WriteLn('3 ', Length(q.A), ' ', q.A[2], ' ', q.B);
  r := nil;
  WriteLn('4 ', Length(r));
end.
