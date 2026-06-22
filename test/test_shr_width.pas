{$mode objfpc}
program test_shr_width;

{ Logical `shr` must operate at the operand's width: a negative 32-bit Integer
  must not leak its sign-extended high bits into the result on 64-bit-register
  targets (bug-shr-signed-integer-width). 64-bit operands and `shl` are
  unaffected. FPC oracle: 2147483644 / 2147483644 / 9223372036854775804 /
  1099511627776 / 256. }

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
end.
