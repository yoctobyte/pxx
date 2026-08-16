program test_high_low_word_aliases;
{ High/Low of the 64-bit machine-word TYPE ALIASES. Every value is FPC 3.2.2's.

  `High(Int64)` folded and `High(NativeInt)` did not — "expected an ordinal
  type name" — although the names already mapped to a kind; OrdinalTypeBound
  simply had no row for tyNativeInt, and SizeInt had no name mapping at all.
  That is the idiomatic way FPC code spells a machine-word bound, and it is
  also how an array is sized (`array[0..High(PtrInt) shr 62]`).

  The UNSIGNED 64-bit names (QWord/UInt64/NativeUInt/PtrUInt) are deliberately
  still refused: their High is 2^64-1, which the constant evaluator's Int64
  cannot carry, and answering -1 would turn a refusal into a wrong value.
  bug-p-high-low-reject-the-64-bit-type-aliases }

const
  NI = High(NativeInt) shr 60;
var
  okc, total: Integer;
  a: array[0..High(PtrInt) shr 62] of Byte;

procedure Chk(const nm: string; got, want: Int64);
begin
  Inc(total);
  if got = want then begin Inc(okc); WriteLn('ok ', nm); end
  else WriteLn('FAIL ', nm, ' got ', got, ' want ', want);
end;

begin
  okc := 0; total := 0;
  Chk('high-nativeint', High(NativeInt), 9223372036854775807);
  Chk('low-nativeint',  Low(NativeInt),  -9223372036854775807 - 1);
  Chk('high-ptrint',    High(PtrInt),    9223372036854775807);
  Chk('low-ptrint',     Low(PtrInt),     -9223372036854775807 - 1);
  Chk('high-sizeint',   High(SizeInt),   9223372036854775807);
  Chk('low-sizeint',    Low(SizeInt),    -9223372036854775807 - 1);
  { the ones that already worked, so the new rows cannot cost them }
  Chk('high-int64',     High(Int64),     9223372036854775807);
  Chk('high-integer',   High(Integer),   2147483647);
  Chk('high-byte',      High(Byte),      255);
  Chk('low-shortint',   Low(ShortInt),   -128);
  { in CONST and array-bound position, which is what the fold exists for }
  Chk('const-fold',     NI,              7);
  Chk('array-bound',    SizeOf(a),       2);
  WriteLn('total ok ', okc, ' / ', total);
end.
