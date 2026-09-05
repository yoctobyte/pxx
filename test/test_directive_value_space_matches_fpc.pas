program test_directive_value_space_matches_fpc;
{ The unknown-DIRECTIVE census keys on the directive NAME, so a directive pxx
  knows carrying a value it does not is structurally invisible to it. Censusing
  fpc 3.2.2's own sources for VALUES instead turned up two: $ALIGN ON / OFF
  (5 uses) and $ASMMODE gas (17 uses), both refused outright.

  Every row here asserts a RELATION between two spellings rather than a byte
  count, so it carries no per-target width and stays true where the natural
  alignment of Int64 is already 4. }

{ ---- $ALIGN ON is $A+, and $ALIGN OFF is $A- ---- }
{$ALIGN ON}
type TAlignOn  = record a: Byte; b: Int64; c: Byte; end;
{$A+}
type TAPlus    = record a: Byte; b: Int64; c: Byte; end;
{$ALIGN OFF}
type TAlignOff = record a: Byte; b: Int64; c: Byte; end;
{$A-}
type TAMinus   = record a: Byte; b: Int64; c: Byte; end;
{$ALIGN 4}
type TAlign4   = record a: Byte; b: Int64; c: Byte; end;
{$A4}
type TA4       = record a: Byte; b: Int64; c: Byte; end;
{$PACKRECORDS 8}
type TPack8    = record a: Byte; b: Int64; c: Byte; end;

{ ---- the two spellings are one setting, so ON and OFF must still DIFFER;
       a pair of rows that agree because both directives were ignored would
       otherwise pass every row above. ---- }

{$ASMMODE gas}      { 17 uses in fpc's own sources; refused before today }
{$ASMMODE standard} { 0 uses -- in the accept-list because fpc takes it }
{$ASMMODE att}
{$ASMMODE intel}
{$ASMMODE default}
{ No asm block anywhere in this file: the directive is written defensively at
  the top of a unit that never assembles a line, which is the case that made
  refusing a non-Intel value pure conformance loss. }

procedure Row(const nm: AnsiString; got, want: Boolean);
begin
  if got = want then WriteLn(nm, ' ok') else WriteLn(nm, ' WRONG');
end;

begin
  Row('align-on = A+  ', SizeOf(TAlignOn) = SizeOf(TAPlus), True);
  Row('align-off = A- ', SizeOf(TAlignOff) = SizeOf(TAMinus), True);
  Row('align-4 = A4   ', SizeOf(TAlign4) = SizeOf(TA4), True);
  Row('on <> off      ', SizeOf(TAlignOn) = SizeOf(TAlignOff), False);
  Row('on = align-4   ', SizeOf(TAlignOn) = SizeOf(TAlign4), True);
  Row('off < on       ', SizeOf(TAlignOff) < SizeOf(TAlignOn), True);
  Row('on < pack-8    ', SizeOf(TAlignOn) < SizeOf(TPack8), True);
  WriteLn('asmmode values accepted with no asm block');
end.
