program test_const_cast_width_matches_runtime;
{ A CONST-expression integer cast must truncate to the same width the RUNTIME
  cast does. `ConstIntCastWidth` was a THIRD copy of the builtin type-name
  table -- name to width+signedness -- and it hardcoded NativeInt, PtrInt,
  NativeUInt and PtrUInt to 8 bytes, which is false on every 32-bit target.
  The runtime chain had already been corrected; this one had not.

      const A = NativeInt(4294967296 + 5);      i386/arm32/riscv32: 4294967301
      var a: NativeInt; a := 4294967296 + 5;                              5

  The same cast, in the same program, folded two different ways -- and the
  const one produced a value that does not fit the type on that target. It was
  filed as a refactor with "not a bug today: nothing observably differs"; it
  differs on three of our targets.

  THE ASSERTION IS AGREEMENT, NOT A CONSTANT. Every row compares the constant
  fold against the runtime cast of the same expression, so the test carries no
  per-target expected values and cannot be satisfied by a table that is
  self-consistently wrong -- x86-64 legitimately prints the wide answer and
  32-bit targets the narrow one, and both are correct. The width is also
  checked against SizeOf of the type itself, which is the independent quantity:
  a fold that agrees with the runtime cast but at the wrong width would still
  fail that row.

  THE PINNED COMPILER CANNOT BUILD THIS FILE, and that is the second half of
  the fix rather than a problem with the test: it rejects `SizeInt(W)` with
  "not a constant", because the private list never accepted sizeint/sizeuint
  while the shared table has always known them. So the pre-fix control is the
  smaller probe in the ticket, which pinned does build, and on i386 it shows the
  four pointer-sized rows folding to 4294967301 against a runtime 5 while the
  Integer control agrees at 5.

  x86-64 CANNOT DETECT THE ORIGINAL DEFECT -- there 8 is the right answer, so
  every row passes on the host. Run it on i386/arm32/riscv32 too; that is where
  the population is. refactor-a-the-const-cast-width-table-is-the-third-copy }

const
  W = 4294967296 + 5;   { 2^32 + 5: survives 8 bytes, truncates to 5 in 4 }
  N = 300;              { survives 2 bytes, truncates in 1 }

  cNativeInt  = NativeInt(W);   cPtrInt    = PtrInt(W);
  cNativeUInt = NativeUInt(W);  cPtrUInt   = PtrUInt(W);
  cSizeInt    = SizeInt(W);     cSizeUInt  = SizeUInt(W);
  cInt64      = Int64(W);       cUInt64    = UInt64(W);   cQWord = QWord(W);
  cInteger    = Integer(W);     cLongInt   = LongInt(W);
  cCardinal   = Cardinal(W);    cLongWord  = LongWord(W); cDWord = DWord(W);
  cSmallInt   = SmallInt(N);    cWord      = Word(N);
  cShortInt   = ShortInt(N);    cByte      = Byte(N);

var
  vNativeInt: NativeInt;   vPtrInt: PtrInt;
  vNativeUInt: NativeUInt; vPtrUInt: PtrUInt;
  vSizeInt: SizeInt;       vSizeUInt: SizeUInt;
  vInt64: Int64;           vUInt64: UInt64;   vQWord: QWord;
  vInteger: Integer;       vLongInt: LongInt;
  vCardinal: Cardinal;     vLongWord: LongWord; vDWord: DWord;
  vSmallInt: SmallInt;     vWord: Word;
  vShortInt: ShortInt;     vByte: Byte;
  fails: Integer;

procedure Chk(const nm: AnsiString; c, v: Int64; declSize, wantSize: Integer);
begin
  if c <> v then
  begin
    WriteLn('FAIL ', nm, ' const=', c, ' runtime=', v);
    fails := fails + 1;
  end;
  if declSize <> wantSize then
  begin
    WriteLn('FAIL ', nm, ' SizeOf=', declSize, ' expected ', wantSize);
    fails := fails + 1;
  end;
end;

begin
  fails := 0;
  vNativeInt := W;  vPtrInt := W;  vNativeUInt := W;  vPtrUInt := W;
  vSizeInt := W;    vSizeUInt := W;
  vInt64 := W;      vUInt64 := W;  vQWord := W;
  vInteger := W;    vLongInt := W;
  vCardinal := W;   vLongWord := W; vDWord := W;
  vSmallInt := N;   vWord := N;    vShortInt := N;    vByte := N;

  { pointer-sized by definition -- the four rows the defect was in }
  Chk('NativeInt',  cNativeInt,  vNativeInt,  SizeOf(NativeInt),  SizeOf(Pointer));
  Chk('PtrInt',     cPtrInt,     vPtrInt,     SizeOf(PtrInt),     SizeOf(Pointer));
  Chk('NativeUInt', cNativeUInt, vNativeUInt, SizeOf(NativeUInt), SizeOf(Pointer));
  Chk('PtrUInt',    cPtrUInt,    vPtrUInt,    SizeOf(PtrUInt),    SizeOf(Pointer));
  { the shared table knows these; the old private list did not accept them }
  Chk('SizeInt',    cSizeInt,    vSizeInt,    SizeOf(SizeInt),    SizeOf(Pointer));
  Chk('SizeUInt',   cSizeUInt,   vSizeUInt,   SizeOf(SizeUInt),   SizeOf(Pointer));

  { CONTROLS: fixed-width names, identical on every target. These are what a
    merge that derived the width from the wrong kind would break, and nothing
    above would notice -- the four rows above are correct on x86-64 either way. }
  Chk('Int64',    cInt64,    vInt64,    SizeOf(Int64),    8);
  Chk('UInt64',   cUInt64,   vUInt64,   SizeOf(UInt64),   8);
  Chk('QWord',    cQWord,    vQWord,    SizeOf(QWord),    8);
  Chk('Integer',  cInteger,  vInteger,  SizeOf(Integer),  4);
  Chk('LongInt',  cLongInt,  vLongInt,  SizeOf(LongInt),  4);
  Chk('Cardinal', cCardinal, vCardinal, SizeOf(Cardinal), 4);
  Chk('LongWord', cLongWord, vLongWord, SizeOf(LongWord), 4);
  Chk('DWord',    cDWord,    vDWord,    SizeOf(DWord),    4);
  Chk('SmallInt', cSmallInt, vSmallInt, SizeOf(SmallInt), 2);
  Chk('Word',     cWord,     vWord,     SizeOf(Word),     2);
  Chk('ShortInt', cShortInt, vShortInt, SizeOf(ShortInt), 1);
  Chk('Byte',     cByte,     vByte,     SizeOf(Byte),     1);

  { the narrow rows must actually have truncated, or the whole matrix is
    agreeing about an operation that never happened }
  if cByte = N then begin WriteLn('FAIL Byte did not truncate'); fails := fails + 1; end;
  if cSmallInt <> N then begin WriteLn('FAIL SmallInt truncated and should not'); fails := fails + 1; end;

  if fails = 0 then
    WriteLn('CONST CAST OK ptr=', SizeOf(Pointer), ' native=', cNativeInt);
end.
