program test_a_longword_against_a_signed_operand_compares_in_int64;
{$mode objfpc}
{ A LongWord against a signed operand compares in Int64 on EVERY target (the
  pair widens to a type holding both). i386/arm32/riscv32 compared it in 32-bit
  signed registers, so 3000000000 read as negative; and QWord against Int64
  compared unsigned there, signed on x86-64/aarch64 and in FPC.
  bug-p-a-longword-against-a-signed-operand-compares-32-bit-signed-on-32-bit-targets }
var
  c, m: LongWord; si: SmallInt; sh: ShortInt; i: LongInt;
  q: QWord; n: Int64;
  arr: array[0..1] of LongWord;

function Big: LongWord; begin Big := 4000000000; end;

begin
  c := 3000000000; m := $FFFFFFFF; si := -1; sh := -1; i := -1;
  q := 9000000000000000000; n := -1;
  arr[1] := 2147483648;
  WriteLn('c > si   ', c > si);
  WriteLn('c < i    ', c < i);
  WriteLn('c >= sh  ', c >= sh);
  WriteLn('i <= c   ', i <= c);
  WriteLn('m = i    ', m = i);
  WriteLn('m <> i   ', m <> i);
  WriteLn('c > -1   ', c > -1);
  WriteLn('-5 < c   ', -5 < c);
  WriteLn('arr > i  ', arr[1] > i);
  WriteLn('Big > i  ', Big > i);
  if c > i then WriteLn('if c > i taken') else WriteLn('if c > i not taken');
  while c < i do c := 0;
  WriteLn('while kept ', c);
  WriteLn('q > n    ', q > n);
  WriteLn('n < q    ', n < q);
  WriteLn('q = n    ', q = n);
  WriteLn('q > i    ', q > i);
  WriteLn('c > 10   ', c > 10);
  WriteLn('c < 4000000000 ', c < 4000000000);
end.
