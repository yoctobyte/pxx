program test_rv32_cast_to_32_bits_is_the_low_word;
{ On riscv32 a cast to a 32-bit integer type, and `x and $FFFFFFFF` at 32
  bits, is the operand's own low word: no sign-extension sequence. Constants
  under not / unary minus / such a cast fold. Values whose high words differ
  from the sign of the low word check the cast wraps, and unsigned results
  of not (which do not fold) still compute. Prints the same on x64. }
{$mode objfpc}
const
  NV = 8;
type
  TPair = record
    a: LongInt;
    b: LongInt;
    c: SmallInt;
  end;
var
  gp: TPair;
  vs: array[0..NV - 1] of Int64;
  i: Integer;
  x: Int64;
  l: LongInt;
  c: Cardinal;
  n: NativeInt;
  b: Byte;
  w: Word;

function Round8(size: NativeInt): NativeInt;
begin
  Result := (size + 7) and (not NativeInt(7));
end;

begin
  vs[0] := 0; vs[1] := 5; vs[2] := -5; vs[3] := $7FFFFFFF; vs[4] := $80000000;
  vs[5] := $1FFFFFFFF; vs[6] := -$80000001; vs[7] := $123456789;
  for i := 0 to NV - 1 do
  begin
    x := vs[i];
    l := LongInt(x);
    c := Cardinal(x);
    n := NativeInt(x and $FFFF) - NativeInt(x and $FF);
    writeln(i, ': ', l, ' ', c, ' ', n, ' ', LongInt(x + 1), ' ', Cardinal(x) + 1,
      ' ', LongInt(x) and $FFFFFFFF, ' ', Int64(LongInt(x)), ' ', Round8(NativeInt(x and $FFFF)),
      ' ', LongInt(Cardinal(x)));
  end;
  writeln('consts: ', NativeInt(7), ' ', not NativeInt(7), ' ', LongInt($FFFFFFFF),
    ' ', -NativeInt(9), ' ', not LongInt(0), ' ', LongInt(-2147483647 - 1));
  b := 7; w := 7; c := 7;
  writeln('unsigned not: ', Byte(not b), ' ', Word(not w), ' ', not c, ' ', Cardinal(not Cardinal(7)));
  { a folded not / negation stored into a field: the store's constant path }
  gp.a := -7; gp.b := not 3; gp.c := -(-12);
  writeln('fields: ', gp.a, ' ', gp.b, ' ', gp.c);
  writeln('round8: ', Round8(0), ' ', Round8(1), ' ', Round8(8), ' ', Round8(13), ' ', Round8(-3));
end.
