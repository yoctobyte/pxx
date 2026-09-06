{ `file of string[N]`: the record width must be the width the variable actually
  HAS, and for N <= 255 that is the FPC shortstring layout -- a one-byte length
  prefix and N characters, so 11 bytes for string[10].

  It was refused outright with `the variable is 24 bytes and the file's element
  type is 11`, and 24 is `cap + 8` rounded up: the eight-byte length word of the
  legacy overloaded tyString. FileIOArgSize read the CAPACITY off the symbol and
  the KIND off the AST node, and an ident node for a frozen string carries
  tyString whatever the symbol is (measured: nodeTk=4, symTk=25, symCap=10).
  Two arguments to one sizer, describing one variable, out of two records.

  THE BYTE COUNT IS THE ASSERTION AND FileSize ON THE TYPED HANDLE IS NOT.
  FileSize counts RECORDS, so it answers 2 under either layout. Every path that
  copies a shortstring normalises the prefix, so the VALUES round-trip correctly
  under either layout too -- a values-and-records row cannot fail here, which is
  precisely the shape that let one Pascal type carry two layouts in one program
  with every size assertion agreeing. Reopening the same file as `file of Byte`
  and counting is what discriminates: 22 can only come from an 11-byte record.

  THE BIG-N ROWS ARE THE CONTROL THAT SAYS WHY NOBODY FOUND THIS. `string[N]` is
  tyShortString for N <= 255 and tyFixedString above it, and tyFixedString's
  prefix is eight bytes -- the same as tyString's. So the wrong kind gave the
  RIGHT answer above 255 and `file of string[300]` compiled all along. Reaching
  for the big case first shows a working feature.

  ROW_MISMATCH is the positive control: a genuine width disagreement must still
  be refused, or the fix is "stop checking" wearing the shape of "check
  correctly". It also reads 256 rather than the old 264 -- the same field being
  wrong made the DIAGNOSTIC wrong, not only the decision.

  WHAT WAS COMPARED WITH FPC AND WHAT COULD NOT BE. The string[10] half is fpc
  3.2.2's, measured rather than reasoned: the identical program under fpc
  -Mobjfpc prints the same values and the same record count, and the file it
  writes is BYTE-IDENTICAL to ours at 22 bytes. The string[300] rows have no
  oracle at all -- fpc caps a shortstring at 255 and refuses the declaration --
  so 312 is OUR layout for the wide kind and is asserted as ours. Both halves
  are in one file because the boundary between them is the bug's whole tell,
  and splitting them to gain an oracle would remove the thing worth testing.
  bug-p-file-of-string-n-refuses-with-a-width-sizeof-contradicts }
program test_a_typed_file_of_string_n_writes_the_shortstring_layout;

uses sysutils;

var
  f: file of string[10];
  fb: file of string[300];
  fbyte: file of Byte;
  t: string[10];
  tb: string[300];
{$IFDEF ROW_MISMATCH}
  big: ShortString;
{$ENDIF}
  tmpdir, pathA, pathB: string;
  n, fails: Integer;

procedure Chk(const what: string; got, want: Integer);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ' got=', got, ' want=', want);
    fails := fails + 1;
  end;
end;

function ByteLen(const path: string): Integer;
begin
  Assign(fbyte, path);
  Reset(fbyte);
  ByteLen := FileSize(fbyte);
  Close(fbyte);
end;

begin
  fails := 0;
  { Same three-step tmpdir as test_typed_file_of_t.pas, and for its reason:
    testmgr passes TESTMGR_TMP and filters TESTTMP out of the environment. }
  tmpdir := GetEnvironmentVariable('TESTMGR_TMP');
  if tmpdir = '' then tmpdir := GetEnvironmentVariable('TESTTMP');
  if tmpdir = '' then tmpdir := '/tmp';
  pathA := tmpdir + '/test_fileofstrn_a.bin';
  pathB := tmpdir + '/test_fileofstrn_b.bin';

{$IFDEF ROW_MISMATCH}
  { A real disagreement: a 256-byte ShortString into an 11-byte record. This
    must NOT compile. It is why the fix reads the symbol's kind rather than
    dropping the comparison. }
  Assign(f, pathA); Rewrite(f); big := 'x'; Write(f, big); Close(f);
{$ENDIF}

  { ---- N <= 255: tyShortString, one-byte prefix, 11 bytes a record ---- }
  Assign(f, pathA); Rewrite(f);
  t := 'hi';     Write(f, t);
  t := 'worlds'; Write(f, t);
  Close(f);

  Reset(f);
  Read(f, t);
  Chk('a.rec0.len', Length(t), 2);
  if t <> 'hi' then begin WriteLn('FAIL a.rec0.val=', t); fails := fails + 1; end;
  Read(f, t);
  Chk('a.rec1.len', Length(t), 6);
  if t <> 'worlds' then begin WriteLn('FAIL a.rec1.val=', t); fails := fails + 1; end;
  n := FileSize(f);
  Close(f);
  Chk('a.records', n, 2);
  Chk('a.sizeof', SizeOf(t), 11);
  { The row the other three cannot make fail. }
  Chk('a.bytes', ByteLen(pathA), 22);

  { ---- N > 255: tyFixedString, eight-byte prefix, 308 aligned to 312.
         Green before the fix and after it; kept so the half that was correct
         by coincidence cannot be regressed by the half that was not. ---- }
  Assign(fb, pathB); Rewrite(fb);
  tb := 'wide'; Write(fb, tb);
  Close(fb);
  Reset(fb);
  Read(fb, tb);
  Chk('b.rec0.len', Length(tb), 4);
  n := FileSize(fb);
  Close(fb);
  Chk('b.records', n, 1);
  Chk('b.sizeof', SizeOf(tb), 312);
  Chk('b.bytes', ByteLen(pathB), 312);

  WriteLn('fails=', fails);
  WriteLn('FILEOFSTRN OK');
end.
