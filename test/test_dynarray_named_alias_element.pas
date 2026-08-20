{ `type TIA2 = array of TIA` (TIA itself `array of Integer`) silently lost a
  dimension: the alias became `array of Integer`, so `m[0][0]` read a heap
  handle as an Integer and printed a different number every run.

    type TIA = array of Integer; TIA2 = array of TIA;
    var m: TIA2; r: TIA;
    ...  m[0] := r;  writeln(m[0][0]);   { was 1233125496, FPC: 7 }
                     writeln(Length(m[0]));  { same garbage }

  The IDENTICAL type spelled at the variable (`var m: array of TIA`) was always
  right -- ParseVarDecl composes an array alias's depth, and the type-alias
  parser did not, so the two spellings of one type disagreed. Only
  `SetLength(m[0], n)` was loud, and only because codegen refuses a depth-1
  target; every read path returned garbage quietly.

  Every expectation is `fpc -O- -Mobjfpc` 3.2.2's.
  bug-p-array-of-a-named-dynamic-array-alias-loses-a-dimension }
program test_dynarray_named_alias_element;
{$mode objfpc}{$H+}
uses sysutils;

type
  TIA   = array of Integer;
  TIA2  = array of TIA;         { alias whose element is a dyn alias }
  TIA3  = array of TIA2;        { and one level deeper }
  TSA   = array of string;
  TSA2  = array of TSA;
  TRec  = record a: Integer; s: string; end;
  TRA   = array of TRec;
  TRA2  = array of TRA;

var
  ok, total: Integer;
  m: TIA2; deep: TIA3; v: array of TIA; r: TIA;
  sm: TSA2; rm: TRA2;
  i, j: Integer; s: string;

procedure Chk(const what: string; got, want: Integer);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got ', got, ' want ', want);
end;

procedure ChkS(const what, got, want: string);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got [', got, '] want [', want, ']');
end;

begin
  ok := 0; total := 0;

  { ---- the alias keeps its dimension ---- }
  SetLength(r, 3); r[0] := 7; r[1] := 8; r[2] := 9;
  SetLength(m, 2);
  m[0] := r;
  Chk('m[0][0] after m[0] := r', m[0][0], 7);
  Chk('m[0][2]', m[0][2], 9);
  Chk('Length(m[0])', Length(m[0]), 3);
  Chk('Length(m)', Length(m), 2);
  Chk('Length(m[1]) (unset row)', Length(m[1]), 0);

  { ---- SetLength on a row of it (was a compile error) ---- }
  SetLength(m[1], 4);
  Chk('Length(m[1]) after SetLength', Length(m[1]), 4);
  m[1][3] := 42;
  Chk('m[1][3]', m[1][3], 42);
  Chk('m[1][0] zeroed', m[1][0], 0);
  Chk('m[0] untouched', m[0][0], 7);

  { ---- multidim SetLength through the alias ---- }
  SetLength(m, 3, 5);
  Chk('multidim Length(m)', Length(m), 3);
  Chk('multidim Length(m[2])', Length(m[2]), 5);
  m[2][4] := -1;
  Chk('m[2][4]', m[2][4], -1);

  { ---- the same type spelled at the VAR still agrees ---- }
  SetLength(v, 2); v[0] := r;
  Chk('v[0][0]', v[0][0], 7);
  Chk('Length(v[0])', Length(v[0]), 3);

  { ---- three levels ---- }
  SetLength(deep, 2);
  SetLength(deep[1], 3);
  SetLength(deep[1][2], 4);
  deep[1][2][3] := 5;
  Chk('Length(deep)', Length(deep), 2);
  Chk('Length(deep[1])', Length(deep[1]), 3);
  Chk('Length(deep[1][2])', Length(deep[1][2]), 4);
  Chk('deep[1][2][3]', deep[1][2][3], 5);
  Chk('deep[1,2,3] comma', deep[1,2,3], 5);

  { ---- a managed element type through the same alias chain ---- }
  SetLength(sm, 2);
  SetLength(sm[0], 2);
  sm[0][0] := 'hello'; sm[0][1] := 'world';
  ChkS('sm[0][1]', sm[0][1], 'world');
  Chk('Length(sm[0])', Length(sm[0]), 2);
  ChkS('sm[1] unset row is empty', IntToStr(Length(sm[1])), '0');

  { ---- and a record element ---- }
  SetLength(rm, 2);
  SetLength(rm[1], 2);
  rm[1][0].a := 3; rm[1][0].s := 'three';
  Chk('rm[1][0].a', rm[1][0].a, 3);
  ChkS('rm[1][0].s', rm[1][0].s, 'three');
  Chk('rm[1][1].a zeroed', rm[1][1].a, 0);

  { ---- iterate it the way real code does ---- }
  SetLength(m, 3);
  for i := 0 to High(m) do
  begin
    SetLength(m[i], i + 1);
    for j := 0 to High(m[i]) do m[i][j] := 10 * i + j;
  end;
  s := '';
  for i := 0 to High(m) do
  begin
    for j := 0 to High(m[i]) do s := s + IntToStr(m[i][j]) + ' ';
    s := s + '|';
  end;
  ChkS('jagged walk', s, '0 |10 11 |20 21 22 |');

  writeln('total ok ', ok, ' / ', total);
end.
