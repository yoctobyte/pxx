program test_ordinal_value_cast_narrows;
{ A value typecast to a narrower ordinal TRUNCATES, in every spelling.

  `Byte(258)` and `Word(65538)` always did. `Char(258)` and `Boolean(256)` did
  not, because ir.inc's narrowing mask excluded tyChar and tyBoolean by name:

    if (narrowSize < 8) and (castTk <> tyBoolean) and (castTk <> tyChar) and
       (castTk <> tyPointer) and TypeIsOrdinal(castTk) then

  Neither exclusion survived contact with the oracle. A Char is a one-byte
  ordinal exactly like the Byte on the same line. The Boolean one carried a
  justification -- "nonzero is true, not the low bit, so masking would turn
  Boolean(256) False" -- and False is exactly what fpc 3.2.2 answers, because it
  narrows to the type's width first and then tests the byte. Only tyPointer
  belongs there, a pointer cast being a reinterpret rather than a narrowing.

  A SECOND defect hid behind the first, and it is the one worth the test:
  `Char` and `Boolean` are lexer TOKENS while `AnsiChar` is an identifier, so
  the two spellings built different AST nodes and took different lowering
  paths. After the mask learned about tyChar, `AnsiChar(258)` answered 2 and
  `Char(258)` still answered 258 -- the same cast, two answers. Both spellings
  now build the one AN_PTR_CAST node.

  bug-p-a-char-cast-does-not-truncate-to-one-byte

  Every row is byte-identical to fpc 3.2.2 -Mobjfpc -O1, on x86-64, i386,
  aarch64, arm32 and riscv32. }
var
  fails: Integer;
  x: Int64;

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

  { the two spellings of one cast must agree }
  ChkI('Char(258)', Ord(Char(x)), 2);
  ChkI('AnsiChar(258)', Ord(AnsiChar(x)), 2);
  x := -1;
  ChkI('Char(-1)', Ord(Char(x)), 255);
  ChkI('AnsiChar(-1)', Ord(AnsiChar(x)), 255);

  { the neighbours that were always right, so a change to the mask cannot
    quietly lose them }
  x := 258;
  ChkI('Byte(258)', Byte(x), 2);
  x := 65538;
  ChkI('Word(65538)', Word(x), 2);
  x := 200;
  ChkI('ShortInt(200)', ShortInt(x), -56);
  x := 258;
  ChkI('WideChar(258)', Ord(WideChar(x)), 258);
  x := 70000;
  ChkI('WideChar(70000)', Ord(WideChar(x)), 4464);
  ChkI('UCS4Char(70000)', Ord(UCS4Char(x)), 70000);

  { Boolean narrows to its BYTE and then tests it, so 256 and 512 are False
    while 257 is True. Asserted through Ord, not as a Boolean: a Boolean holding
    a truthy byte other than 1 compares unequal to True under both compilers
    (`Boolean(2) <> True`), so a Boolean-valued assertion would measure that
    quirk rather than the narrowing. Every row measured against fpc 3.2.2. }
  x := 2;   ChkI('Boolean(2)', Ord(Boolean(x)), 2);
  x := 255; ChkI('Boolean(255)', Ord(Boolean(x)), 255);
  x := 256; ChkI('Boolean(256)', Ord(Boolean(x)), 0);
  x := 257; ChkI('Boolean(257)', Ord(Boolean(x)), 1);
  x := 512; ChkI('Boolean(512)', Ord(Boolean(x)), 0);
  x := 0;   ChkI('Boolean(0)', Ord(Boolean(x)), 0);
  x := -1;  ChkI('Boolean(-1)', Ord(Boolean(x)), 255);
  x := 256;
  if Boolean(x) then
  begin writeln('FAIL Boolean(256) is truthy'); fails := fails + 1; end;
  x := 257;
  if not Boolean(x) then
  begin writeln('FAIL Boolean(257) is falsy'); fails := fails + 1; end;

  { an in-range cast is untouched by any of this }
  x := 81;
  ChkI('Char(81) round trip', Ord(Char(x)), 81);
  ChkI('Byte(81)', Byte(x), 81);

  if fails = 0 then writeln('ALL OK') else writeln(fails, ' FAILURES');
end.
