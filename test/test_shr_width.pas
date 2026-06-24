{$mode objfpc}
program test_shr_width;

{ Logical `shr` must operate at the operand's width: a negative 32-bit Integer
  must not leak its sign-extended high bits into the result on 64-bit-register
  targets (bug-shr-signed-integer-width). `shl` must wrap at the operand width
  too: shifting into bit 31 of a 32-bit Integer reads back negative, while a
  64-bit operand (incl. a UInt64/Int64 cast) keeps its full width
  (bug-shl-signed-integer-width). FPC oracle:
  2147483644 / 2147483644 / 9223372036854775804 / 1099511627776 / 256 /
  -2147483648 / -16 / 2147483648 / 1099511627776 / 4503599627370496. }

var
  i: Integer;
  c: Cardinal;
  q: Int64;
begin
  i := -8;          writeln(i shr 1);          { 2147483644 }
  c := $FFFFFFF8;   writeln(c shr 1);          { 2147483644 }
  q := -8;          writeln(q shr 1);          { 9223372036854775804 }
  writeln(UInt64(1) shl 40);                    { 1099511627776 }
  i := 1024;        writeln(i shr 2);          { 256 }
  i := 1;           writeln(i shl 31);         { -2147483648 (wraps at 32-bit) }
  i := -1;          writeln(i shl 4);          { -16 }
  c := 1;           writeln(c shl 31);         { 2147483648 (unsigned, positive) }
  writeln(UInt64(1) shl 40);                    { 1099511627776 (64-bit unchanged) }
  writeln(Int64(1) shl 52);                     { 4503599627370496 }
end.
