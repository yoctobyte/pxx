program test_rv32_int64_divide_without_libgcc;
{ An Int64/QWord div or mod on riscv32 IDF calls pxx's own out-of-line
  helpers (builtinheap's PXXIDivMod64/PXXUDivMod64), never libgcc's __divdi3
  family. Both operands within 32 bits take one inline div/divu (rem/remu)
  before any call, and a constant divisor in range skips its own fits test
  (the digit loops and seconds-per-day splits); the rest is long division
  on magnitudes with the signs put back (quotient negative when signs differ,
  remainder with the dividend's sign). Every sign combination, the 32-bit
  boundary on both sides, divisors above 2^32, Low(Int64) and the QWord top
  bit, against x86-64. Low(Int64) div -1 is left out: it traps on x86-64;
  Low(LongInt) div -1 is in, the one 32-bit pair whose quotient is not. }
{$mode objfpc}
var
  a, b: Int64;
  ua, ub: QWord;
  i, j: Integer;
  sum: Int64;
const
  SA: array[0..13] of Int64 = (0, 1, 7, -7, 10, 2147483647, 2147483648, -2147483648,
    4294967295, 4294967296, -4294967297, 1234567890123456789, High(Int64), Low(Int64));
  SB: array[0..9] of Int64 = (1, -1, 3, -3, 10, 65536, 4294967295, 4294967296,
    -5000000000, 1000000007);
  QA: array[0..5] of QWord = (0, 99, 4294967295, 4294967296, QWord(1) shl 63, High(QWord));
  QB: array[0..5] of QWord = (1, 7, 4294967295, 4294967296, QWord(1) shl 63, High(QWord));
begin
  for i := 0 to High(SA) do
  begin
    for j := 0 to High(SB) do
    begin
      a := SA[i]; b := SB[j];
      if (a = Low(Int64)) and (b = -1) then Continue;
      write(a div b, ' ', a mod b, ' ');
    end;
    writeln;
  end;
  for i := 0 to High(QA) do
  begin
    for j := 0 to High(QB) do
    begin
      ua := QA[i]; ub := QB[j];
      write(ua div ub, ' ', ua mod ub, ' ');
    end;
    writeln;
  end;
  { constant divisors: in range (no run-time divisor test), negative and out of
    range (tested at run time like a variable) }
  for i := 0 to High(SA) do
  begin
    a := SA[i];
    writeln(a div 10, ' ', a mod 10, ' ', a div 86400, ' ', a mod 86400, ' ',
      a div 2147483647, ' ', a mod 2147483647, ' ', a div -10, ' ', a mod -10, ' ',
      a div 2147483648, ' ', a mod 2147483648);
  end;
  for i := 0 to High(QA) do
  begin
    ua := QA[i];
    writeln(ua div 10, ' ', ua mod 10, ' ', ua div 4294967295, ' ',
      ua mod 4294967295, ' ', ua div 4294967296, ' ', ua mod 4294967296);
  end;
  { a div/mod pair re-forms the dividend }
  sum := 0;
  a := 98765432109876;
  for i := 1 to 500 do
  begin
    b := Int64(i) * 9973 - 2500000;
    if (a div b) * b + (a mod b) <> a then writeln('BAD ', b);
    sum := sum + (a div b) - (a mod b);
    a := -a;
  end;
  writeln(sum);
  writeln('done');
end.
