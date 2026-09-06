program test_read_into_a_frozen_string_from_stdin_and_a_file;
{ Reading into a FROZEN string -- ShortString, string[N] -- was broken in two
  different ways at two different doors, and neither door had a test.

  FROM A TEXT FILE it SEGFAULTED. TextReadStrTo's parameter is
  `var s: AnsiString`, so the destination slot was handed to a managed writer.
  The Char arm beside it had predicted this in writing and stopped one type
  short: "whose `var AnsiString` slot would have written a string handle into
  ONE BYTE".

  FROM STDIN it did not crash and produced a SILENT WRONG VALUE, which is the
  worse of the two. EmitReadVarParse has no frozen arm; its `tyString` case
  writes a QWORD length at [dest] and the characters at dest+8 -- the WORD-prefix
  layout -- so on input 'abc' a ShortString came back with Length = 3 (the low
  byte of that qword, right by accident) and the characters at s[8], s[9], s[10].
  The BYTE DUMP below is the assertion; Length alone passes under the bug.

  Both are now routed through a managed temp and assigned, which is where the
  managed -> frozen narrowing already lives. That is also what supplies the
  CAPACITY CLAMP the stdin path never had: `string[4]` truncates instead of
  writing past its slot.

  .expected is fpc 3.2.2's own output. Input comes from the Makefile rule.
  bug-b-readln-from-a-text-file-into-a-frozen-string-segfaults
  bug-b-read-into-a-frozen-string-uses-the-wrong-prefix-width }
var
  ss: ShortString; s4: string[4]; n: Integer; i: Integer;
  managed: string;
  f: Text;
begin
  { ---- stdin ---- }
  ss := '#########';          { pre-filled, so a short read cannot hide behind zeros }
  ReadLn(ss);
  WriteLn('stdin len=', Length(ss), ' [', ss, ']');
  { WHERE THE BYTES LANDED. Length alone is green under the defect, because the
    qword's low byte IS the right length on a little-endian target -- so the
    only row that can fail is this one. }
  for i := 1 to 12 do Write(Ord(ss[i]), ' ');
  WriteLn;
  { the capacity clamp, which did not exist }
  ReadLn(s4);
  WriteLn('stdin4 [', s4, '] len=', Length(s4));
  { a non-string target on the same statement family, as the control that must
    not move }
  ReadLn(n);
  WriteLn('stdin n=', n);

  { ---- a Text file: this one used to SEGFAULT ---- }
  Assign(f, 'frozenread.tmp'); Rewrite(f);
  WriteLn(f, 'from a file');
  WriteLn(f, 'second line');
  Close(f);
  Assign(f, 'frozenread.tmp'); Reset(f);
  ReadLn(f, ss);
  WriteLn('file  [', ss, '] len=', Length(ss));
  { `read` and not `readln`, which is a separate arm of the same dispatch }
  Read(f, s4);
  WriteLn('file4 [', s4, ']');
  Close(f);

  { CONTROL: a MANAGED destination, which was correct throughout. Without it a
    change that broke every string read would pass every row above. }
  Assign(f, 'frozenread.tmp'); Reset(f);
  ReadLn(f, managed);
  WriteLn('mgd   [', managed, ']');
  Close(f);
  Erase(f);
end.
