program test_rv32_constant_arithmetic_folds;
{ riscv32 folds a + - * and or xor of two integer constants (nested too) when
  the exact result fits the node's type; anything that would wrap, and every
  other operator, still runs. Named constants are where these come from,
  and a folded constant is also a leaf call argument (Fill).
  Each line is computed once from constants and once from variables holding
  the same values, so a fold that changed a value shows as a mismatch on the
  line itself; x86-64 is the oracle for both. }
{$mode objfpc}
const
  NOZERO = $40000000;
  SECS = 30;
  K = 1000;
  BIGC = Int64(3000000000);
  MASK = $FF00;
  RXOFF = 48;
procedure Put32(p: PByte; off: Integer; v: LongWord);
begin
  p[off] := v and 255;
  p[off + 1] := (v shr 8) and 255;
  p[off + 2] := (v shr 16) and 255;
  p[off + 3] := (v shr 24) and 255;
end;

function Pick(p: PByte; neg: Boolean; q: Pointer; w: Integer): Integer;
begin
  Result := p^ + w;
  if neg then Result := -Result;
  if q = nil then Inc(Result, 1000);
end;

procedure Fill;
var buf: array[0..63] of Byte; k: LongInt; sum: LongWord;
begin
  for k := 0 to High(buf) do buf[k] := 0;
  { a folded Int64 constant expression handed to an Integer parameter, after
    an argument that is pushed (as the IDF wifi-init block is written) }
  Put32(@buf[0], RXOFF + 0 * 4, 10);
  Put32(@buf[0], RXOFF + 1 * 4, NOZERO or 7);
  Put32(@buf[0], RXOFF + 2 * 4, SECS * K);
  Put32(@buf[0], 2 * 4, $DEADBEEF);
  sum := 0;
  for k := 0 to High(buf) do sum := sum * 31 + buf[k];
  { Boolean and nil constants as trailing leaf arguments: they are constants,
    but not integer kinds the fold reads }
  writeln('pick ', Pick(@buf[8], True, nil, RXOFF + 1), ' ', Pick(@buf[8], False, @buf[0], 2));
  writeln('fill ', sum, ' ', buf[RXOFF], ' ', buf[RXOFF + 7], ' ', buf[8]);
end;

var
  i8: ShortInt; u8: Byte; i16: SmallInt; u16: Word;
  i32: LongInt; u32: LongWord; i64: Int64; u64: QWord;
  a, b: Int64; la, lb: LongInt;
begin
  i64 := 8 or NOZERO;           a := 8; b := NOZERO;            writeln(i64, ' ', a or b);
  i64 := SECS * K * K;          a := SECS; b := K;              writeln(i64, ' ', a * b * b);
  i64 := BIGC * 3 + 7;          a := BIGC;                      writeln(i64, ' ', a * 3 + 7);
  i64 := BIGC - 4000000000;     a := BIGC; b := 4000000000;     writeln(i64, ' ', a - b);
  i64 := (MASK and $0F0F) xor $FFFF;                            writeln(i64);
  i32 := SECS * K * K;          la := SECS; lb := K;            writeln(i32, ' ', la * lb * lb);
  i32 := -7 * 3 + 100;          la := -7;                       writeln(i32, ' ', la * 3 + 100);
  i32 := 2147483647 - 1;                                        writeln(i32);
  i32 := -2147483647 - 1;                                       writeln(i32);
  u32 := 4000000000 + 1;                                        writeln(u32);
  u32 := $FFFF0000 or $FF;                                      writeln(u32);
  u32 := $F0F0F0F0 xor $0F0F0F0F;                               writeln(u32);
  u16 := 65535 and 255 + 1;                                     writeln(u16);
  i16 := -300 * 100;                                            writeln(i16);
  u8 := 200 + 55;                                               writeln(u8);
  i8 := -100 - 28;                                              writeln(i8);
  u64 := QWord(1) shl 40 + 5;                                   writeln(u64);
  { results past their type: not folded, computed as before }
  la := 2147483647; i32 := 2147483647 + 1 - 1;                  writeln(i32, ' ', la + 1 - 1);
  u8 := Byte(250 + 10);                                         writeln(u8);
  i64 := Int64(3037000500) * 3037000500;                        writeln(i64);
  writeln(SECS * K, ' ', NOZERO or 1, ' ', (BIGC + BIGC) div 3, ' ', MASK - 1);
  Fill;
  writeln('done');
end.
