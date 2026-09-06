program test_qwordbool_is_the_fourth_sized_boolean;
{ `QWordBool` -- FPC's 8-byte C-ABI boolean -- answered `unknown type`, which
  reads as an unimplemented type and was one NAME missing from two tables while
  everything behind it already worked: SemBool(8) = -24 is defs.inc's own worked
  example of SEM_BOOL_BASE, and BoolStorageTypeKind(8) has always returned
  tyInt64. A rule spelled as a list fails by an ABSENT entry, and the three
  entries that were present agreed with each other perfectly.
  ByteBool/WordBool/LongBool ride along as the control: the fourth must behave
  exactly as they do, at eight bytes. tenum6.pp is the corpus row.
  Rows 4-7 are the ones that used to be able to answer BOTH ways
  (bug-p-a-sized-boolean-is-true-and-not-true-at-the-same-time); row 9 is the
  discriminator that needs a value outside the one-bit world. }
var
  b8: ByteBool; b16: WordBool; b32: LongBool; b64: QWordBool;
  s: string;
begin
  b64 := False; Str(b64, s); WriteLn('1 ', s);
  b64 := True;  Str(b64, s); WriteLn('2 ', s);
  WriteLn('3 ', SizeOf(b64), ' ', Ord(b64));
  if b64 then WriteLn('4 then') else WriteLn('4 else');
  if not b64 then WriteLn('5 then') else WriteLn('5 else');
  b64 := False;
  if b64 then WriteLn('6 then') else WriteLn('6 else');
  if not b64 then WriteLn('7 then') else WriteLn('7 else');
  WriteLn('8 ', b64);
  b64 := QWordBool(200);
  WriteLn('9 ', Ord(b64), ' ', b64);
  b8 := True; b16 := True; b32 := True;
  WriteLn('10 ', SizeOf(b8), ' ', SizeOf(b16), ' ', SizeOf(b32), ' ', SizeOf(QWordBool));
  WriteLn('11 ', Ord(b8), ' ', Ord(b16), ' ', Ord(b32), ' ', Ord(b64));
end.
