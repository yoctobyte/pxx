program test_esp_typed_const_array_in_obj;
{ A typed const ARRAY under --emit-obj is baked into .data (riscv32/xtensa
  object writers, 2026-10-12) instead of being filled by startup stores. The
  relocation now names .data, so a wrong section or addend reads garbage:
  every element of every width is read back, one is written ({$J+} typed
  consts are writable), and the output must equal the x86-64 run. }
const
  Bytes: array[3..9] of Byte = (42, 0, 255, 7, 128, 1, 99);
  Ints: array[0..4] of Integer = (-1, 0, 2147483647, -2147483647, 12345);
  Big: array[0..2] of Int64 = (1234567890123, -5, 9007199254740993);
  Dbl: array[0..2] of Double = (1.5, -0.25, 1048576.0);
  Words: array[1..3] of Word = (65535, 0, 4660);
var i: Integer; s: Int64;
begin
  s := 0;
  for i := 3 to 9 do s := s * 3 + Bytes[i];
  WriteLn('bytes ', s);
  for i := 0 to 4 do Write(Ints[i], ' ');
  WriteLn;
  for i := 0 to 2 do Write(Big[i], ' ');
  WriteLn;
  for i := 0 to 2 do Write(Trunc(Dbl[i] * 4), ' ');
  WriteLn;
  for i := 1 to 3 do Write(Words[i], ' ');
  WriteLn;
  Ints[2] := 7;
  WriteLn('written ', Ints[2], ' ', Ints[1], ' ', Ints[3]);
end.
