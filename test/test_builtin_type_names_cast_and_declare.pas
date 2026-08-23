program test_builtin_type_names_cast_and_declare;
{ Every built-in scalar type name must mean the SAME thing in a cast as in a
  declaration.

  It used not to. The name->kind table existed twice: ParseTypeKind knew ~40
  names, the built-in typecast in pasparser_expr.inc knew a ~12-name subset.
  So a name added to the declaration site did not become CASTABLE --
  `var b: ByteBool` compiled and `ByteBool(2)` was "undefined variable
  (ByteBool)", along with WordBool, LongBool, Comp, ValReal, TDateTime,
  Currency, SizeUInt, UTF8String, RawByteString, OleVariant and CodePointer,
  every one of them a legal cast in FPC.

  Worse, where the two tables overlapped they disagreed: the cast chain called
  `longint` tyInteger where the declaration said tyInt32, and `nativeint` /
  `ptrint` / `nativeuint` / `ptruint` tyInt64/tyUInt64 where the declaration
  said the pointer-sized kinds. The last one is not cosmetic -- NativeInt is
  pointer-sized BY DEFINITION, so the cast claimed 8 bytes on i386, arm32,
  riscv32 and xtensa where the declaration of the same name gives 4.

  bug-a-the-builtin-type-name-table-exists-twice-and-the-two-disagree

  The pointer-sized rows below are asserted as decl-size = cast-size rather
  than against a literal, which is what makes this test meaningful on a 32-bit
  target: it is the AGREEMENT that is under test, not a number.

  Values verified identical to fpc 3.2.2 -Mobjfpc -O1. }
var
  fails: Integer;
  x: Int64;
  vbb: ByteBool; vwb: WordBool; vlb: LongBool;
  vi8: Int8; vi16: Int16; vi32: Int32; vli: LongInt; vc: Cardinal; vq: QWord;
  vni: NativeInt; vnu: NativeUInt; vpi: PtrInt; vpu: PtrUInt;
  vsi: SizeInt; vsu: SizeUInt; vcmp: Comp;
  vac: AnsiChar; vwc: WideChar; vu4: UCS4Char;
  vcp: CodePointer; vdt: TDateTime; vcy: Currency; vvr: ValReal; vov: OleVariant;

procedure ChkI(const what: AnsiString; got, want: Int64);
begin
  if got <> want then
  begin
    writeln('FAIL ', what, ': got ', got, ' want ', want);
    fails := fails + 1;
  end;
end;

begin
  fails := 0;
  x := 258;

  { ---- the names that could not be CAST at all ---- }
  ChkI('ByteBool value', Ord(ByteBool(x)), 2);      { truncates to one byte }
  ChkI('WordBool value', Ord(WordBool(x)), 258);
  ChkI('LongBool value', Ord(LongBool(x)), 258);
  ChkI('Comp size', SizeOf(Comp(x)), 8);
  ChkI('TDateTime size', SizeOf(TDateTime(x)), 8);
  ChkI('Currency size', SizeOf(Currency(x)), 8);
  ChkI('UCS4Char value', Ord(UCS4Char(x)), 258);
  ChkI('WideChar value', Ord(WideChar(x)), 258);

  { ---- a cast means what the DECLARATION of the same name means ---- }
  ChkI('ByteBool', SizeOf(ByteBool(x)), SizeOf(vbb));
  ChkI('WordBool', SizeOf(WordBool(x)), SizeOf(vwb));
  ChkI('LongBool', SizeOf(LongBool(x)), SizeOf(vlb));
  ChkI('Int8', SizeOf(Int8(x)), SizeOf(vi8));
  ChkI('Int16', SizeOf(Int16(x)), SizeOf(vi16));
  ChkI('Int32', SizeOf(Int32(x)), SizeOf(vi32));
  ChkI('LongInt', SizeOf(LongInt(x)), SizeOf(vli));
  ChkI('Cardinal', SizeOf(Cardinal(x)), SizeOf(vc));
  ChkI('QWord', SizeOf(QWord(x)), SizeOf(vq));
  ChkI('Comp', SizeOf(Comp(x)), SizeOf(vcmp));
  ChkI('AnsiChar', SizeOf(AnsiChar(x)), SizeOf(vac));
  ChkI('WideChar', SizeOf(WideChar(x)), SizeOf(vwc));
  ChkI('UCS4Char', SizeOf(UCS4Char(x)), SizeOf(vu4));
  ChkI('CodePointer', SizeOf(CodePointer(x)), SizeOf(vcp));
  ChkI('TDateTime', SizeOf(TDateTime(x)), SizeOf(vdt));
  ChkI('Currency', SizeOf(Currency(x)), SizeOf(vcy));
  { ValReal is FPC's "widest available real", so under fpc it is the 10-byte
    x87 Extended and here it is Double -- a deliberate divergence
    (feature-extended-alias-or-reject: Extended aliases Double on every
    target). So only the AGREEMENT is asserted, never a literal width. }
  ChkI('ValReal', SizeOf(ValReal(x)), SizeOf(vvr));

  { the pointer-sized family: 8 on x86-64/aarch64, 4 on i386/arm32/riscv32.
    The cast used to answer tyInt64 -- a flat 8 -- on every one of them. }
  ChkI('NativeInt', SizeOf(NativeInt(x)), SizeOf(vni));
  ChkI('NativeUInt', SizeOf(NativeUInt(x)), SizeOf(vnu));
  ChkI('PtrInt', SizeOf(PtrInt(x)), SizeOf(vpi));
  ChkI('PtrUInt', SizeOf(PtrUInt(x)), SizeOf(vpu));
  ChkI('SizeInt', SizeOf(SizeInt(x)), SizeOf(vsi));
  ChkI('SizeUInt', SizeOf(SizeUInt(x)), SizeOf(vsu));
  ChkI('NativeInt is pointer-sized', SizeOf(NativeInt(x)), SizeOf(Pointer(x)));
  ChkI('SizeUInt is pointer-sized', SizeOf(SizeUInt(x)), SizeOf(Pointer(x)));

  { OleVariant declares and casts; a Variant is 16 bytes here }
  ChkI('OleVariant', SizeOf(vov), SizeOf(Variant(x)));

  { ---- and the widths themselves, which are fixed by the language ---- }
  ChkI('ByteBool is 1', SizeOf(vbb), 1);
  ChkI('WordBool is 2', SizeOf(vwb), 2);
  ChkI('LongBool is 4', SizeOf(vlb), 4);
  ChkI('LongInt is 4', SizeOf(vli), 4);
  ChkI('WideChar is 2', SizeOf(vwc), 2);
  ChkI('UCS4Char is 4', SizeOf(vu4), 4);

  if fails = 0 then writeln('ALL OK') else writeln(fails, ' FAILURES');
end.
