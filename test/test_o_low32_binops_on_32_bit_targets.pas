{ An integer +, -, *, and/or/xor whose result is stored to 4 bytes or less
  runs at 32 bits on the 32-bit backends (one multiply, not the pair path).
  The VALUES are the claim; the count is a separate row.
  bug-o-every-integer-multiply-emits-four-multiplies-on-the-32-bit-backends-and-one-is-enough }
program test_o_low32_binops_on_32_bit_targets;
var i, j, q: Integer; w, x: LongWord; s: SmallInt; b: Byte; c: Int64; k: Integer;
    arr: array[0..3] of Integer; p, p2: PInteger;
begin
  i := 123456 + ParamCount; j := -98765 - ParamCount;
  q := i * j; WriteLn(q);
  q := i * j + i - j * 3; WriteLn(q);
  q := (i xor j) and (i or 77); WriteLn(q);
  w := 4000000000; x := 3; w := w * x; WriteLn(w);
  w := LongWord(i) * 70000; WriteLn(w);
  s := 300; s := s * s; WriteLn(s);
  b := 200; b := b * 3 + 1; WriteLn(b);
  c := Int64(i) * j; WriteLn(c);
  k := 2147483647; k := k + 1; WriteLn(k);
  k := -2147483647 - 1; k := k * (-1); WriteLn(k);
  arr[0] := 1; arr[1] := 2; arr[2] := 3; arr[3] := 4;
  p := @arr[0]; p2 := PInteger(PtrUInt(p) + 2 * SizeOf(Integer)); WriteLn(p2^);
  for k := 0 to 3 do arr[k] := arr[k] * k - 1; WriteLn(arr[0], ' ', arr[1], ' ', arr[2], ' ', arr[3]);
end.
