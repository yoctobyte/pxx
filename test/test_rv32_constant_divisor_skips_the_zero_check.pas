program test_rv32_constant_divisor_skips_the_zero_check;
{ riscv32 tested every divisor for zero before div/mod, constants included.
  A divisor that is an integer constant other than zero now skips the test:
  32-bit div/mod (signed, unsigned, narrowed from wider types) on its low
  word, Int64/UInt64 on the whole value. A 64-bit constant whose low word is
  zero ($100000000) must still divide by the whole value. Values only, so
  x86-64 is the oracle; MinInt div -1 is left out (x86 traps there). }
{$mode objfpc}
var
  i: LongInt;
  c: LongWord;
  k: Int64;
  u: QWord;
  b: Byte;
  sum: Int64;
begin
  sum := 0;
  for i := -1000 to 1337 do
    sum := sum + i div 7 + i mod 7 + i div -3 + i mod -3 + i div 100 + i mod 100 + i div 1 + i mod 1 + i div -1;
  writeln(sum);
  c := 4000000000;
  writeln(c div 10, ' ', c mod 10, ' ', c div 3, ' ', c mod 65536, ' ', c div 4096);
  i := -123456789;
  writeln(i div 1000, ' ', i mod 1000, ' ', i div 2048, ' ', i mod 4097, ' ', i div 2147483647);
  b := 250;
  writeln(b div 7, ' ', b mod 7);
  k := 123456789012345;
  writeln(k div 1000, ' ', k mod 1000, ' ', k div -7, ' ', k mod -7, ' ', k div $100000000, ' ', k mod $100000000);
  k := -98765432109876;
  writeln(k div 10, ' ', k mod 10, ' ', k div 3000000000, ' ', k mod 3000000000);
  k := 77;
  writeln(k div 5, ' ', k mod 5, ' ', k div $100000000);
  u := QWord($F000000000000001);
  writeln(u div 10, ' ', u mod 10, ' ', u div $100000000, ' ', u mod $100000000);
  writeln('done');
end.
