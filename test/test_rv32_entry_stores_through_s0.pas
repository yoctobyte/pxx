program test_rv32_entry_stores_through_s0;
{ riscv32 stores incoming parameters and zeroes managed locals at function
  entry through s0 directly (`sw a0, off(s0)`) when the slot is within its
  12-bit reach, and through t0 = s0 + off only when it is not. Every spill
  shape -- byte, word, longint, Int64, a by-value set, a 5-8 byte record,
  words past a7 on the caller's stack -- and managed locals placed beyond
  2 KB of frame (the t0 fallback) must read back what was passed. Compared
  with x86-64; run under -dPXX_ALLOC_CENSUS for the managed locals. }
{$mode objfpc}
type
  TPair = record a, b: LongInt; end;
  TSmall = set of 0..200;
var gs: AnsiString;

function Spill(b: Byte; w: Word; sh: ShortInt; i: LongInt; q: Int64; c: Char;
               s: TSmall; p: TPair; u: QWord; e: Integer; f: Int64; g: Byte): AnsiString;
var t: AnsiString; k: Integer;
begin
  Str(b, t); Result := t;
  Str(w, t); Result := Result + ' ' + t;
  Str(sh, t); Result := Result + ' ' + t;
  Str(i, t); Result := Result + ' ' + t;
  Str(q, t); Result := Result + ' ' + t + ' ' + c;
  for k := 0 to 200 do if k in s then begin Str(k, t); Result := Result + ' ' + t; end;
  Str(p.a, t); Result := Result + ' ' + t;
  Str(p.b, t); Result := Result + ' ' + t;
  Str(u, t); Result := Result + ' ' + t;
  Str(e, t); Result := Result + ' ' + t;
  Str(f, t); Result := Result + ' ' + t;
  Str(g, t); Result := Result + ' ' + t;
end;

function Far(n: Integer; const tag: AnsiString): AnsiString;
var big: array[0..2999] of Byte; s1, s2: AnsiString; v: Variant; k, sum: Integer;
begin
  { s1, s2 and v are zeroed at entry; with 3000 bytes of array beside them
    some of the slots are past s0's reach }
  for k := 0 to 2999 do big[k] := Byte(k * n);
  sum := 0;
  for k := 0 to 2999 do sum := sum + big[k];
  if s1 = '' then s1 := tag;
  if s2 = '' then s2 := '+';
  v := sum;
  Result := s1 + s2 + tag;
  Str(Integer(v), s1);
  Result := Result + ' ' + s1;
end;

function FarParams(big: array of Byte; x: Int64; y: Byte): AnsiString;
var pad: array[0..2499] of Byte; s: AnsiString; k: Integer;
begin
  for k := 0 to 2499 do pad[k] := y;
  Str(x + pad[2499] + Length(big), s);
  Result := s;
end;

var p: TPair; st: TSmall; bb: array[0..9] of Byte; i: Integer;  { gs is reused below }
begin
  p.a := -7; p.b := 123456;
  st := [0, 5, 64, 199, 200];
  writeln(Spill(250, 65000, -100, -2147483000, -1234567890123, 'Z', st, p,
                18446744073709551615, -42, 9000000000, 7));
  for i := 1 to 3 do writeln(Far(i, 'x'));
  { the same calls again, many times, for the allocation census }
  for i := 1 to 60 do
  begin
    gs := Spill(1, 2, 3, 4, 5, 'q', st, p, 6, 7, 8, 9) + Far(i, 'y');
    if Length(gs) = 0 then writeln('empty');
  end;
  writeln(FarParams(bb, 5000000000, 9));
  gs := 'done';
  writeln(gs);
end.
