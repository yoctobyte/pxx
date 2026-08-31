{ How many captures a lifted nested routine may carry. The lift turns each
  captured enclosing local into a trailing by-reference parameter, and the
  guard on that was a literal 16 while the staging arrays and TProc.Params are
  both MAX_PROC_PARAMS = 32 wide -- so half the space that exists was refused,
  with a diagnostic that reads like a real limit.

  It bit for real: collapsing ParseSubroutine's three copies of the durable
  param row into one nested PersistParamRow captures 21 staging arrays, and the
  first build after that collapse died on this guard rather than on any array
  bound.

  Positive control, which is why the counts here are 20 and not 5: `pinned`
  refuses the scalar half of this file with "nested routine: too many params
  after capture". The upper bound is still enforced -- 40 captures is still
  refused today. }
program test_nested_capture_param_bound;

var checked: Integer;

procedure Chk(c: Boolean; const tag: AnsiString);
begin
  if c then Inc(checked) else WriteLn('FAIL ', tag);
end;

function ScalarCaptures: Integer;   { 20 scalar captures }
var v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15, v16, v17, v18, v19: Integer;
  procedure Inner;
  begin
    v0 := 0;
    v1 := 1;
    v2 := 2;
    v3 := 3;
    v4 := 4;
    v5 := 5;
    v6 := 6;
    v7 := 7;
    v8 := 8;
    v9 := 9;
    v10 := 10;
    v11 := 11;
    v12 := 12;
    v13 := 13;
    v14 := 14;
    v15 := 15;
    v16 := 16;
    v17 := 17;
    v18 := 18;
    v19 := 19;
  end;
var s, k: Integer;
begin
  Inner;
  s := 0;
  s := s + v0;
  s := s + v1;
  s := s + v2;
  s := s + v3;
  s := s + v4;
  s := s + v5;
  s := s + v6;
  s := s + v7;
  s := s + v8;
  s := s + v9;
  s := s + v10;
  s := s + v11;
  s := s + v12;
  s := s + v13;
  s := s + v14;
  s := s + v15;
  s := s + v16;
  s := s + v17;
  s := s + v18;
  s := s + v19;
  k := 0; if s > 0 then k := 1;
  ScalarCaptures := s;
end;

function ArrayCaptures: Integer;    { 20 fixed-array captures }
var
  a0: array[0..1] of Integer;
  a1: array[0..1] of Integer;
  a2: array[0..1] of Integer;
  a3: array[0..1] of Integer;
  a4: array[0..1] of Integer;
  a5: array[0..1] of Integer;
  a6: array[0..1] of Integer;
  a7: array[0..1] of Integer;
  a8: array[0..1] of Integer;
  a9: array[0..1] of Integer;
  a10: array[0..1] of Integer;
  a11: array[0..1] of Integer;
  a12: array[0..1] of Integer;
  a13: array[0..1] of Integer;
  a14: array[0..1] of Integer;
  a15: array[0..1] of Integer;
  a16: array[0..1] of Integer;
  a17: array[0..1] of Integer;
  a18: array[0..1] of Integer;
  a19: array[0..1] of Integer;
  procedure Inner;
  begin
    a0[0] := 0; a0[1] := 0;
    a1[0] := 1; a1[1] := 2;
    a2[0] := 2; a2[1] := 4;
    a3[0] := 3; a3[1] := 6;
    a4[0] := 4; a4[1] := 8;
    a5[0] := 5; a5[1] := 10;
    a6[0] := 6; a6[1] := 12;
    a7[0] := 7; a7[1] := 14;
    a8[0] := 8; a8[1] := 16;
    a9[0] := 9; a9[1] := 18;
    a10[0] := 10; a10[1] := 20;
    a11[0] := 11; a11[1] := 22;
    a12[0] := 12; a12[1] := 24;
    a13[0] := 13; a13[1] := 26;
    a14[0] := 14; a14[1] := 28;
    a15[0] := 15; a15[1] := 30;
    a16[0] := 16; a16[1] := 32;
    a17[0] := 17; a17[1] := 34;
    a18[0] := 18; a18[1] := 36;
    a19[0] := 19; a19[1] := 38;
  end;
var s: Integer;
begin
  Inner;
  s := 0;
  s := s + a0[0] + a0[1];
  s := s + a1[0] + a1[1];
  s := s + a2[0] + a2[1];
  s := s + a3[0] + a3[1];
  s := s + a4[0] + a4[1];
  s := s + a5[0] + a5[1];
  s := s + a6[0] + a6[1];
  s := s + a7[0] + a7[1];
  s := s + a8[0] + a8[1];
  s := s + a9[0] + a9[1];
  s := s + a10[0] + a10[1];
  s := s + a11[0] + a11[1];
  s := s + a12[0] + a12[1];
  s := s + a13[0] + a13[1];
  s := s + a14[0] + a14[1];
  s := s + a15[0] + a15[1];
  s := s + a16[0] + a16[1];
  s := s + a17[0] + a17[1];
  s := s + a18[0] + a18[1];
  s := s + a19[0] + a19[1];
  ArrayCaptures := s;
end;

begin
  checked := 0;
  Chk(ScalarCaptures = 190, 'scalar');       { 0+1+..+19 }
  Chk(ArrayCaptures = 570, 'array');         { 190 + 380 }
  WriteLn('NESTED CAPTURE PARAM BOUND OK checked=', checked);
end.
