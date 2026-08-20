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
    4   Single
    8   Double
    8   Real        (Double on this target, as in FPC)
   10   Extended
   16   Variant     (pxx's own 16-byte tagged value: 8 tag + 8 payload; FPC's
                     TVarData is 24 -- a representation difference, not a bug)
    2   WideChar
    4   UCS4Char
    1   AnsiChar
    8   String      (a handle)
    8   AnsiString

  The block from Single down was REJECTED outright until BuiltinTypeNameTk:
  SizeOf kept a private copy of the builtin type-name table covering only the
  integer family, Boolean, Char and String, so `SizeOf(Double)` -- a type the
  compiler otherwise supports fully -- was a compile error. Every value here
  agrees with FPC 3.2.2 except Variant, whose representation differs as noted.
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

  { The float family, Variant, and the wide character kinds -- the names the
    intrinsic's own table used to be missing }
  writeln(SizeOf(Single));
  writeln(SizeOf(Double));
  writeln(SizeOf(Real));
  writeln(SizeOf(Extended));
  writeln(SizeOf(Variant));
  writeln(SizeOf(WideChar));
  writeln(SizeOf(UCS4Char));
  writeln(SizeOf(AnsiChar));
  writeln(SizeOf(String));
  writeln(SizeOf(AnsiString));
end.
