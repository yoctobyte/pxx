program test_div_mod_negative_dividend_pow2;
{$mode objfpc}{$H+}
{ Negative dividends over CONSTANT powers of two -- the one case the div/mod
  strength reduction can get wrong, and the only case it can get wrong.
  A bare `sar` FLOORS; Pascal `div` truncates toward zero and `mod` takes the
  sign of the DIVIDEND, so the signed path must bias by (2^k - 1) first
  (`sar 63; shr 64-k; add`) before shifting.

  WHY THIS FILE EXISTS. The pass was promoted from -O3 to -O2 in 13d4bba0c and
  ships in every binary the compiler emits. Its promotion ticket
  (perf-o-promote-constant-divisor-strength-reduction-to-o2) made a differential
  over signed dividends a CONDITION of promoting -- and that condition was never
  met: the nearest test, test_div_mod_mixed_signedness, uses VARIABLE divisors,
  so the reduction needs IR_CONST_INT and never fires in it. The pass was
  correct; nothing was testing that it stayed correct.

  SENSITIVITY, verified rather than assumed. Deleting the bias sequence and
  leaving a bare `sar rax, k` makes 28 of these 35 lines wrong (`-1 div 2`
  answers -1 instead of 0). The pass fires here: -O0 emits 85 idiv and 1 sar,
  -O2 emits 49 idiv, 55 sar and 54 shr -- 36 divisions reduced.

  -O0 is the CONTROL: the guard is `OptLevel >= 2`, so -O0 provably cannot use
  the pass and must produce the same answers by idiv. All three levels are
  asserted against ONE expectation, which is FPC 3.2.2's output. }
var
  i8: ShortInt; i16: SmallInt; i32: LongInt; i64: Int64;
  vals: array[0..8] of Int64 = (-1, -7, -8, -9, -15, -16, -17, -1023, -1024);
  k: Integer;
begin
  for k := 0 to 8 do
  begin
    i64 := vals[k];
    Write('q64 ', i64 div 2, ' ', i64 div 4, ' ', i64 div 8, ' ', i64 div 16, ' ', i64 div 1024);
    WriteLn(' r64 ', i64 mod 2, ' ', i64 mod 4, ' ', i64 mod 8, ' ', i64 mod 16, ' ', i64 mod 1024);
    i32 := LongInt(vals[k]);
    Write('q32 ', i32 div 2, ' ', i32 div 4, ' ', i32 div 8, ' ', i32 div 16);
    WriteLn(' r32 ', i32 mod 2, ' ', i32 mod 4, ' ', i32 mod 8, ' ', i32 mod 16);
    i16 := SmallInt(vals[k]);
    Write('q16 ', i16 div 2, ' ', i16 div 4, ' ', i16 div 8, ' ', i16 div 16);
    WriteLn(' r16 ', i16 mod 2, ' ', i16 mod 4, ' ', i16 mod 8, ' ', i16 mod 16);
    if (vals[k] >= -128) then
    begin
      i8 := ShortInt(vals[k]);
      Write('q8 ', i8 div 2, ' ', i8 div 4, ' ', i8 div 8, ' ', i8 div 16);
      WriteLn(' r8 ', i8 mod 2, ' ', i8 mod 4, ' ', i8 mod 8, ' ', i8 mod 16);
    end;
  end;
  WriteLn('done');
end.
