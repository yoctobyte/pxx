{ IOResult reports FPC's codes, never a raw negative errno.

  The bug this closes was silent: pxx passed the errno straight through, so a
  missing file gave -2 where FPC gives 2 and `if IOResult = 2 then` — an
  entirely ordinary thing to write — took the wrong branch in correct Pascal
  source. `if IOResult <> 0`, which is how most code spells it, was unaffected,
  which is exactly why it could sit undetected.

  EVERY expectation here was MEASURED against fpc 3.2.2 by producing the
  condition and reading IOResult back. That mattered more than usual, because
  FPC's behaviour is not the clean translation the ticket assumed:

    * it maps a KNOWN set and passes everything else through as the positive
      errno — ELOOP comes back as 40, its own errno, not a DOS-style code. The
      ELOOP row below is load-bearing: it is the one that proves the `else` arm
      is FPC's behaviour rather than a fallback we invented;
    * `path not found` answers 2, NOT the 3 the ticket predicted from DOS
      heritage. Documentation said 3; the oracle says 2;
    * ENAMETOOLONG maps to 2 rather than passing through as 36, so the mapped
      set is genuinely a map and not just an absolute-value.

  The rows deliberately NOT here are EPERM and EROFS, which could not be
  produced without root. They take the passthrough path and may differ from
  FPC. An unverified row in this table would be worse than a missing one: it
  would look measured. }
program lib_ioresult_fpc_codes;

uses textfile, platform, sysutils;

var
  failures: Integer;
  dir: AnsiString;

procedure Fail(const what, got, want: AnsiString);
begin
  Inc(failures);
  WriteLn('FAIL ', what, ': got ', got, ' want ', want);
end;

procedure CheckI(const what: AnsiString; got, want: Integer);
begin
  if got <> want then Fail(what, IntToStr(got), IntToStr(want));
end;

{ Open `path` for reading (or writing) with checks off and return the code. }
function OpenCode(const path: AnsiString; wr: Boolean): Integer;
var f: Text;
begin
  {$I-}
  Assign(f, path);
  if wr then Rewrite(f) else Reset(f);
  Result := IOResult;
  Close(f);
  if IOResult = 0 then ;
  {$I+}
end;

var
  f: Text;
  long, perm, loop1, loop2, sub, okf: AnsiString;
  code: Integer;

begin
  failures := 0;
  dir := GetEnvironmentVariable('TESTTMP');
  if dir = '' then dir := GetTempDir;
  if (Length(dir) > 0) and (dir[Length(dir)] <> '/') then dir := dir + '/';

  okf := dir + 'ioc_ok.dat';
  {$I-} Assign(f, okf); Rewrite(f); TextWriteLn(f, 'hi'); Close(f);
  if IOResult = 0 then ; {$I+}

  { --- the headline row: a missing file is 2, not -2 --- }
  CheckI('missing file', OpenCode(dir + 'ioc_definitely_missing_xyz', False), 2);

  { A missing intermediate directory. FPC answers 2 here, not 3 — measured. }
  CheckI('path not found', OpenCode(dir + 'ioc_nodir/sub/file.dat', False), 2);

  { ENOTDIR: a path that runs THROUGH a regular file. }
  CheckI('ENOTDIR (file/sub)', OpenCode(okf + '/sub', False), 5);

  { ENAMETOOLONG maps to 2 — a map, not a passthrough (errno is 36). }
  long := dir;
  while Length(long) < Length(dir) + 300 do long := long + 'z';
  CheckI('ENAMETOOLONG', OpenCode(long, False), 2);

  { EISDIR: rewriting a directory. TESTTMP itself is one. }
  sub := dir + 'ioc_adir';
  PalMkdir(PChar(sub), 493);
  CheckI('EISDIR (rewrite a dir)', OpenCode(sub, True), 5);

  { ELOOP: a symlink cycle. THE row that proves the passthrough arm — FPC
    reports 40, the raw errno, rather than any DOS-style code. }
  loop1 := dir + 'ioc_loop1';
  loop2 := dir + 'ioc_loop2';
  {$I-} Assign(f, loop1); Erase(f); if IOResult = 0 then ;
        Assign(f, loop2); Erase(f); if IOResult = 0 then ; {$I+}
  PalSymlink(PChar(loop2), PChar(loop1));
  PalSymlink(PChar(loop1), PChar(loop2));
  CheckI('ELOOP (passthrough)', OpenCode(loop1, False), 40);

  { EACCES. Guarded: running as a user who can read anything (root, or a
    filesystem that ignores modes) makes the open SUCCEED, and asserting 5 then
    would be asserting the environment rather than the code. The skip is
    PRINTED, not silent — an invisible skip is how a suite passes without
    testing anything. }
  perm := dir + 'ioc_perm.dat';
  {$I-} Assign(f, perm); Rewrite(f); TextWriteLn(f, 'hi'); Close(f);
  if IOResult = 0 then ; {$I+}
  PalChmod(PChar(perm), 0);
  code := OpenCode(perm, False);
  if code = 0 then
    WriteLn('  skip EACCES: this user can read a mode-000 file')
  else
    CheckI('EACCES', code, 5);
  PalChmod(PChar(perm), 420);

  { Success is still 0. }
  CheckI('success', OpenCode(okf, False), 0);

  { The two states that are not errnos at all: FPC's 103 (not open) and 102
    (not assigned). These used to share the -1 sentinel with EPERM, which is a
    real errno — so the sentinel was ambiguous as well as negative. }
  {$I-}
  Assign(f, okf);
  TextWrite(f, 'x');            { never opened }
  CheckI('write to unopened handle', IOResult, 103);

  Assign(f, '');
  Erase(f);                     { no name assigned }
  CheckI('erase with no name', IOResult, 102);

  Assign(f, okf);
  Reset(f);
  if IOResult = 0 then ;
  Rename(f, dir + 'ioc_renamed.dat');   { still open }
  CheckI('rename an open handle', IOResult, 102);
  Close(f);
  if IOResult = 0 then ;
  {$I+}

  { The invariant behind all of it, asserted as itself: no failure may ever
    surface a negative IOResult, whatever the cause. }
  if OpenCode(dir + 'ioc_definitely_missing_xyz', False) < 0 then
    Fail('no negative codes', 'negative', 'positive');
  if OpenCode(loop1, False) < 0 then
    Fail('no negative codes (passthrough arm)', 'negative', 'positive');

  if failures = 0 then
    WriteLn('IORESULTCODES OK')
  else
    WriteLn('IORESULTCODES FAILED ', failures);
end.
