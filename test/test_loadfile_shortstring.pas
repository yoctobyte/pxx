{ LoadFile into a SHORTSTRING -- the raw `EmitLoadFile` arm in symtab.inc.

  It clamps a negative read() to zero with `jns +10` over one `MovRaxImm(0)`.
  MovRaxImm picks its encoding from the immediate and emits TWO bytes for zero,
  so the jump cleared the clamp AND the eight bytes after it, which are the
  start of EmitStoreStrLen. On the successful read -- the only path anyone
  takes -- the length was never stored and every LoadFile into a ShortString
  returned an EMPTY string:

      p := 'test/test_loadfile_shortstring.data';
      LoadFile(p, s);  WriteLn(Length(s))   printed 0, for a 21-byte file

  test_loadfile_into_element_and_field and test_cross_loadfile both declare
  AnsiString destinations, which route to EmitLoadFileManaged -- a different
  emitter -- so the arm was uncovered rather than passing.

  There is no FPC oracle for LoadFile; the file's length is the assertion.
  bug-a-hand-written-literal-short-jumps-span-emitters-that-can-grow }
program test_loadfile_shortstring;
var p, s: ShortString;
begin
  p := 'test/test_loadfile_shortstring.data';
  LoadFile(p, s);
  WriteLn('len   ', Length(s));            { 21: 'shortstring-loadfile' + LF }
  WriteLn('text  [', s:0, ']');
  { a path that does not exist: read() is never reached, open() fails, and the
    clamp is what must leave a well-formed empty string rather than a length
    read out of a negative fd. }
  p := 'test/no-such-file-here.data';
  LoadFile(p, s);
  WriteLn('miss  ', Length(s));            { 0 }
  WriteLn('LOADFILE SHORTSTRING OK');
end.
