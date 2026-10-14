program test_rv32_int64_op_constant;
{ On riscv32 a 64-bit op with a constant right operand skips the move of
  the left operand to t0:t1: and/or/xor go word by word in place, = and <>
  test each word's difference, signed < 0 and >= 0 read the sign bit, and
  + * and the ordered compares load the constant as the left operand
  (mirrored). Every constant shape against signed and unsigned values whose
  words straddle the boundaries. Prints the same on x64. }
{$mode objfpc}
const
  NV = 12;
var
  vs: array[0..NV - 1] of Int64;
  us: array[0..NV - 1] of QWord;
  i: Integer;
  x: Int64;
  u: QWord;
  w: LongWord;
  li: LongInt;

function B(c: Boolean): Char;
begin
  if c then Result := 'T' else Result := 'F';
end;

begin
  vs[0] := 0; vs[1] := 1; vs[2] := -1; vs[3] := 2047; vs[4] := -2048;
  vs[5] := $7FFFFFFF; vs[6] := $80000000; vs[7] := $FFFFFFFF;
  vs[8] := $100000000; vs[9] := -$100000000; vs[10] := High(Int64);
  vs[11] := Low(Int64);
  for i := 0 to NV - 1 do us[i] := QWord(vs[i]);

  for i := 0 to NV - 1 do
  begin
    x := vs[i];
    write(i, ' and: ', x and 0, ' ', x and -1, ' ', x and 255, ' ', x and $FFFFFFFF,
      ' ', x and $FFFFFFFF00000000, ' ', x and $12345, ' ', x and -16,
      ' ', x and $80000000, ' ', x and $100000000);
    writeln;
    write(i, ' or: ', x or 0, ' ', x or -1, ' ', x or 128, ' ', x or $FFFFFFFF,
      ' ', x or $100000000, ' ', x or -2048, ' ', x or $7FFFF);
    writeln;
    write(i, ' xor: ', x xor 0, ' ', x xor -1, ' ', x xor 1, ' ', x xor $FFFFFFFF,
      ' ', x xor $100000000, ' ', x xor -11, ' ', x xor $ABCDE);
    writeln;
    writeln(i, ' eq: ', B(x = 0), B(x <> 0), B(x = 1), B(x = -1), B(x <> -1),
      B(x = 2047), B(x = -2048), B(x = $7FFFFFFF), B(x = $80000000),
      B(x = $FFFFFFFF), B(x <> $100000000), B(x = -$100000000),
      B(x = High(Int64)), B(x = Low(Int64)), B(x = 4096));
    writeln(i, ' lt: ', B(x < 0), B(x >= 0), B(x > 0), B(x <= 0), B(x < 1),
      B(x > -1), B(x < 2047), B(x >= -2048), B(x > $7FFFFFFF),
      B(x <= $80000000), B(x < $100000000), B(x >= -$100000000), B(x > 60000));
    writeln(i, ' arith: ', x + 4096, ' ', x + $100000000, ' ', x + 60000,
      ' ', x * 4, ' ', x * 10, ' ', x * 1000, ' ', x * -3, ' ', x * $100000001);
    u := us[i];
    writeln(i, ' u: ', u and $FF, ' ', u or $F0000000, ' ', u xor $FFFFFFFF,
      ' ', B(u = 0), B(u <> $FFFFFFFF), B(u < 1), B(u >= 1), B(u > 0),
      B(u <= $80000000), B(u > $FFFFFFFF), B(u < $100000000),
      ' ', u + 70000, ' ', u * 1000);
  end;

  { 32-bit-typed constants widened by their own type: LongWord zero-extends,
    LongInt sign-extends }
  w := $FFFFFFFF; li := -5;
  for i := 0 to NV - 1 do
  begin
    x := vs[i];
    writeln(i, ' w: ', x and w, ' ', x and LongWord($80000000), ' ', x + LongWord(70000),
      ' ', B(x = LongWord($FFFFFFFF)), B(x < LongWord($80000000)),
      ' ', x and li, ' ', x + LongInt(-70000), ' ', B(x = LongInt(-1)), B(x < LongInt(-1)));
  end;
end.
