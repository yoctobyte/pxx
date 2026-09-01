{ The builtin `PWord` means ^UInt16 in a USER program, even though the RTL units
  that program pulls in declare a machine-word pointer of their own.

  builtinheap and builtinwide each declared `PWord = ^NativeInt` in their
  IMPLEMENTATION section, on the stated belief that an implementation section is
  private. It is not: pxx has no interface/implementation visibility boundary at
  all -- a unit's implementation-section types, consts AND routines are visible
  to every importer (FPC rejects all four). builtinheap reaches essentially every
  program, so its alias shadowed the builtin `PWord` everywhere, and

      PWord(p)^        read EIGHT bytes instead of two
      PWord(p)^ := x   WROTE eight bytes instead of two

  silently, at every -O level, in any program that spelled the ordinary name
  PWord. The write is the dangerous half: six bytes of whatever followed.

  It survived because it is the ONLY leaked alias whose meaning DISAGREES with
  the builtin of the same name -- the sibling leaks (PByte, PInt64, PInt32,
  PDouble, PLongInt, PSingle, PVariant) all happen to match, so the leak is
  invisible for them. `builtin.pas` had already learned this and spells the type
  `PMachineWord`; builtinheap and builtinwide now do too.

  The `own declaration still wins` direction is test_builtin_pointer_types_b303.
  The leak itself is bug-p-a-units-implementation-section-is-visible-to-its-importers.

  FPC 3.2.2 agrees with every row below EXCEPT that it cannot compile this
  program at all -- `uses builtinheap` is a pxx builtin unit. The oracle was run
  on the same rows without that line, where FPC gives 2 / 30600 / 30600 / 136 /
  30600 / -120 / 1432778632 / 1432778632 / 1234605616436508552 and the same
  two-byte writes. Measured, not reasoned. The `uses builtinheap` here is not
  decoration: it is the shadowing VECTOR, and the test is pointless without it. }
program test_builtin_pword_not_shadowed_by_rtl;
{$mode objfpc}{$H+}
uses builtinheap;

var
  buf: array[0..7] of Byte;
  a: Pointer;
  i, fail: Integer;

procedure Chk(const what: AnsiString; got, want: Int64);
begin
  if got <> want then
  begin WriteLn('FAIL ', what, ' = ', got, ' want ', want); Inc(fail); end;
end;

begin
  fail := 0;
  buf[0] := $88; buf[1] := $77; buf[2] := $66; buf[3] := $55;
  buf[4] := $44; buf[5] := $33; buf[6] := $22; buf[7] := $11;
  a := @buf[0];

  { the width itself }
  Chk('SizeOf(PWord^)', SizeOf(PWord(a)^), 2);

  { a deref used INLINE in an expression -- this is the shape that was wrong.
    Assigning to a Word variable narrowed at the STORE and so looked correct. }
  Chk('PWord^ inline', PWord(a)^, 30600);
  Chk('PWord^ in arithmetic', PWord(a)^ + 0, 30600);

  { the siblings, which never disagreed -- they are the control that says this
    test is about shadowing and not about derefs in general }
  Chk('PByte^', PByte(a)^, 136);
  Chk('PSmallInt^', PSmallInt(a)^, 30600);
  Chk('PShortInt^', PShortInt(a)^, -120);
  Chk('PCardinal^', PCardinal(a)^, 1432778632);
  Chk('PLongInt^', PLongInt(a)^, 1432778632);
  Chk('PInt64^', PInt64(a)^, 1234605616436508552);

  { the WRITE half: exactly two bytes, five neighbours untouched }
  for i := 0 to 7 do buf[i] := $FF;
  PWord(a)^ := 0;
  Chk('write byte0', buf[0], 0);
  Chk('write byte1', buf[1], 0);
  for i := 2 to 7 do Chk('write neighbour untouched', buf[i], 255);

  { a wide RHS must still store only two bytes -- the store width comes from the
    POINTEE, not from the value }
  for i := 0 to 7 do buf[i] := 0;
  PWord(a)^ := $1122334455667788;
  Chk('wide RHS byte0', buf[0], 136);
  Chk('wide RHS byte1', buf[1], 119);
  for i := 2 to 7 do Chk('wide RHS neighbour untouched', buf[i], 0);

  WriteLn('fail=', fail);
  if fail = 0 then WriteLn('PWORDSHADOW OK') else WriteLn('PWORDSHADOW FAILED');
end.
