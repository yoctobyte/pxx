{ A function returning a record whose result local sits deeper than 128 bytes
  into the frame. The xtensa WINDOWED ABI stores the hidden result pointer at
  that local's offset, and the store was built with addi's 8-bit immediate
  only: past it the compiler refused ("aggregate-result frame offset out of
  range"). A 120 B record hit it -- and lib/rtl/regex.pas's ReRunAt, so no Nil
  Python program importing `re` built for the S3. Three sizes: 120 B (just
  past imm8), 1 KB (a movi-sized offset) and 8 KB (past movi, so the literal
  pool). x86-64 is the oracle.
  bug-a-xtensa-windowed-an-aggregate-result-past-128-bytes-of-frame-does-not-compile }
program test_xtensa_windowed_large_aggregate_result;

type
  T120 = record ok: Boolean; n: Integer; a, b: array[0..13] of Integer; end;
  T1K  = record n: Integer; a: array[0..254] of Integer; end;
  T8K  = record n: Integer; a: array[0..2046] of Integer; end;

function Make120(k: Integer): T120;
var m: T120; i: Integer;
begin
  m.ok := k > 0; m.n := k;
  for i := 0 to 13 do begin m.a[i] := i * k; m.b[i] := i + k; end;
  Make120 := m;
end;

function Make1K(k: Integer): T1K;
var m: T1K; i: Integer;
begin
  m.n := k;
  for i := 0 to 254 do m.a[i] := i * k;
  Make1K := m;
end;

function Make8K(k: Integer): T8K;
var m: T8K; i: Integer;
begin
  m.n := k;
  for i := 0 to 2046 do m.a[i] := i + k;
  Make8K := m;
end;

var r: T120; s: T1K; t: T8K;
begin
  r := Make120(3);
  WriteLn(r.ok, ' ', r.n, ' ', r.a[13], ' ', r.b[13]);
  s := Make1K(2);
  WriteLn(s.n, ' ', s.a[0], ' ', s.a[127], ' ', s.a[254]);
  t := Make8K(5);
  WriteLn(t.n, ' ', t.a[0], ' ', t.a[1023], ' ', t.a[2046]);
end.
