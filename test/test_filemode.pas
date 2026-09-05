program test_filemode;
{ System.FileMode: the access mode `Reset` opens a typed or untyped file with.
  0 = read-only, 1 = write-only, anything else = read/write, default 2.

  WHY IT IS A VARIABLE AND NOT A CONSTANT. Real code SETS it. FPC's own
  cstreams.pas is the reason this exists here at all:

      oldfilemode:=filemode;
      filemode:=$40 or Mode;
      system.assign(FHandle,AFileName);
      {$push} {$I-} system.reset(FHandle,1);

  — save, force, open, restore. That is the standard way to open a file
  read-only in Pascal when you do not control the Reset call, and it was the
  blocker for four units of the FPC compiler-source march once `file of T`
  landed. Reset previously hardcoded the mode-2 behaviour and merely NAMED
  FileMode in a comment, so a caller that set it got no error and no effect.

  THE DISCRIMINATING ROW IS `readonly write refused`, AND THE SPELLING MATTERS.
  PAL_OPEN_READ / _WRITE / _RDWR are 0 / 1 / 2 — the SAME NUMBERS as FileMode's
  own 0 / 1 / 2, because both follow the POSIX convention. So a test that sets
  `FileMode := 0` cannot tell a working mapping from NO MAPPING AT ALL: passing
  the value straight through unexamined gives the right answer for every plain
  value. The expected value collides with the do-nothing value, which is the
  guard-that-cannot-fail shape CLAUDE.md warns about under "choose a probe whose
  right answer differs from the default".

  `$40 or 0` is the probe that separates them. $40 is a SHARE bit
  (fmShareDenyNone), which we must mask off because we do not lock — and 64 is
  not 0, 1 or 2, so an implementation that failed to mask would fall through to
  the read/write default and the write below would SUCCEED. That is the only row
  here whose right answer is not also the answer you get for free.

  All five rows are byte-for-byte fpc 3.2.2's own output for this program.
  bug-p-an-unqualified-call-to-a-user-routine-named-read-or-write-is-eaten-by-the-intrinsic
  feature-pascal-typed-and-untyped-files }
{$MODE OBJFPC}
uses sysutils;
var
  f: file of Integer;
  i, ok, tot: Integer;
  path: AnsiString;

procedure Chk(const s: AnsiString; got, want: Integer);
begin
  Inc(tot);
  if got = want then begin Inc(ok); writeln('ok   ', s); end
  else writeln('FAIL ', s, ': got ', got, ' want ', want);
end;

begin
  ok := 0; tot := 0;
  path := GetEnvironmentVariable('TMPDIR');
  if path = '' then path := '/tmp';
  path := path + '/test_filemode.dat';

  Assign(f, path); Rewrite(f); i := 7; Write(f, i); Close(f);

  { default FileMode = 2: read-modify-write through ONE handle, no reopen }
  Assign(f, path); Reset(f);
  Read(f, i);                       Chk('default reads', i, 7);
  Seek(f, 0); i := 99; Write(f, i);
  Close(f);
  Assign(f, path); Reset(f); Read(f, i);
                                    Chk('default wrote', i, 99);
  Close(f);

  { read-only, spelled the way cstreams.pas spells it }
  FileMode := $40 or 0;
  Assign(f, path); Reset(f);
  Read(f, i);                       Chk('readonly reads', i, 99);
  Seek(f, 0); i := 123;
  {$I-} Write(f, i); {$I+}
  Chk('readonly write refused', Ord(IOResult <> 0), 1);
  Close(f);
  FileMode := 2;

  Assign(f, path); Reset(f); Read(f, i);
                                    Chk('unchanged on disk', i, 99);
  Close(f);

  writeln('total ok ', ok, ' / ', tot);
end.
