{ test/test_sizeof.pas
  Phase 1 regression: verify SizeOf returns the correct byte sizes for all
  Pascal scalar types. These tests document the TYPE CONTRACT from
  docs/types-and-targets.md.

  Expected output (one value per line):
    1   Byte
    1   ShortInt
    2   Word
    2   SmallInt
    4   Integer
    4   LongInt
    4   Cardinal
    4   LongWord
    8   Int64
    8   QWord
    8   NativeInt   (x86-64 target: pointer-sized = 8)
    8   NativeUInt
    8   PtrInt
    8   PtrUInt
    8   Pointer
    1   Char
    1   Boolean
}
program TestSizeOf;
begin
  { 1-byte types }
  writeln(SizeOf(Byte));
  writeln(SizeOf(ShortInt));

  { 2-byte types }
  writeln(SizeOf(Word));
  writeln(SizeOf(SmallInt));

  { 4-byte types }
  writeln(SizeOf(Integer));
  writeln(SizeOf(LongInt));
  writeln(SizeOf(Cardinal));
  writeln(SizeOf(LongWord));

  { 8-byte types }
  writeln(SizeOf(Int64));
  writeln(SizeOf(QWord));

  { Pointer-sized types (8 on x86-64) }
  writeln(SizeOf(NativeInt));
  writeln(SizeOf(NativeUInt));
  writeln(SizeOf(PtrInt));
  writeln(SizeOf(PtrUInt));
  writeln(SizeOf(Pointer));

  { Character/boolean }
  writeln(SizeOf(Char));
  writeln(SizeOf(Boolean));
end.
