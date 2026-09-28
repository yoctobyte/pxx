program test_an_int64_cast_of_a_fields_address_widens_the_pointer;
{$mode objfpc}
{ `Int64(@r.f)` over an Int64 (or Double, or QWord) field is the ADDRESS widened
  to 64 bits. The address node carried the FIELD's kind, so the cast skipped
  the widen and i386/arm32/riscv32 read a garbage high word:
  `Int64(@r.i) - Int64(@r)` was 4294967297 for a field at offset 1.
  bug-a-an-int64-cast-of-an-int64-fields-address-keeps-a-garbage-high-word }
type
  TP = packed record c: Char; i: Int64; d: Double; q: QWord; b: Byte; end;
  TA = packed record pad: Byte; v: array[0..2] of Int64; end;
var
  r: TP;
  a: TA;
  base, x: Int64;
  u: QWord;
begin
  base := Int64(@r);
  WriteLn('i ', Int64(@r.i) - base);
  WriteLn('d ', Int64(@r.d) - base);
  WriteLn('q ', Int64(@r.q) - base);
  WriteLn('b ', Int64(@r.b) - base);
  x := Int64(@r.i);
  WriteLn('stored ', x - base);
  u := QWord(@r.q);
  WriteLn('qword ', Int64(u) - base);
  WriteLn('elem ', Int64(@a.v[2]) - Int64(@a));
  WriteLn('high zero ', (Int64(@r.i) shr 32) = (base shr 32));
end.
