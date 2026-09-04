program test_shortstring_is_string_255;
{ `ShortString` and `string[255]` are ONE Pascal type with two spellings, and
  they must have one layout.

  The phase-4 flip (`fd186a975`) moved `string[N]` to FPC's one-byte length
  prefix and did not move the `shortstring` arm sitting nine lines below it, so
  for a day the two spellings disagreed: 264 bytes with data at offset 8 against
  256 with data at offset 1, in the same program.

  IT WAS A WRONG VALUE, NOT A WIDTH. Every path that COPIED between them
  normalised and agreed -- assignment, a value parameter, Length, WriteLn -- so
  the whole thing read green. A `var` parameter does not copy: it aliases the
  caller's storage and the callee reads the prefix at its own declared width.
  `ViaVarShortString(s255)` printed Length = 122511465736197 and 4KB of
  whitespace, from ordinary declared source, with no diagnostic.

  SO THE SIZE ROW IS NOT THE GUARD HERE, AND CANNOT BE. Measured against a
  control compiler carrying only this revert: `SizeOf(ShortString) =
  SizeOf(v: ShortString)` still read OK, because both spellings of the broken
  half were broken identically. `spelling` compares the two SPELLINGS, `layout`
  reads the PHYSICAL bytes, and `varparam` crosses the two through the one
  construct that cannot normalise. Those three failed; the size rows did not.

  `delegated` is the other half of the same ticket and is here rather than in
  test_sizeof_builtin_type_names.pas for one reason: it is the only row of it
  that is TARGET-sensitive. PChar is 4 bytes on the 32-bit targets and TextFile
  is a record either way, so a delegation that resolved a name against a fixed
  width would pass on x86-64 and fail here.
  bug-p-sizeof-of-a-type-name-is-settled-against-a-kind-that-cannot-express-the-size

  Byte-identical under FPC 3.2.2 on every row. }

type
  TS255 = string[255];

var
  ss: ShortString; s255: TS255;
  vSS: ShortString; vPC: PChar; vPAC: PAnsiChar; vPWC: PWideChar; vTF: TextFile;

function ByteAt(p: Pointer; n: Integer): Byte;
var q: ^Byte;
begin
  q := Pointer(PtrUInt(p) + PtrUInt(n));
  ByteAt := q^;
end;

procedure Row(const what: AnsiString; ok: Boolean);
begin
  if ok then WriteLn(what, ' OK') else WriteLn(what, ' FAIL');
end;

{ The crossing point. A var parameter ALIASES rather than copies, so the callee
  reads the length prefix at whatever width its own declared type claims. }
procedure ViaVarShortString(var s: ShortString);
begin
  WriteLn('varparam   ', Length(s), ' <', s, '>');
end;

begin
  { The five names that took `var v: N` and refused `SizeOf(N)`. A RELATION,
    never a constant: TextFile is 4128 bytes here and 888 under FPC, and this
    file has no business freezing that. }
  Row('delegated  ', (SizeOf(ShortString) = SizeOf(vSS)) and
                     (SizeOf(PChar)       = SizeOf(vPC)) and
                     (SizeOf(PAnsiChar)   = SizeOf(vPAC)) and
                     (SizeOf(PWideChar)   = SizeOf(vPWC)) and
                     (SizeOf(TextFile)    = SizeOf(vTF)));

  Row('spelling   ', SizeOf(ShortString) = SizeOf(TS255));

  ss := 'hello';
  WriteLn('layout     ', ByteAt(@ss, 0), ' ', ByteAt(@ss, 1), ' ', ByteAt(@ss, 2),
          ' ', ByteAt(@ss, 3), ' ', ByteAt(@ss, 4), ' ', ByteAt(@ss, 5));

  s255 := 'hello';
  ViaVarShortString(s255);
end.
