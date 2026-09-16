{ System's MkDir / RmDir / ChDir and the IOResult codes they report.

  THE LOAD-BEARING ROWS ARE THE ONES A SINGLE SHARED ERRNO TABLE WOULD FAIL.
  Every code here was produced by making the condition happen under fpc 3.2.2
  and reading IOResult back -- fpc documents none of them -- and two rows
  disagree with the table the FILE routines in this unit already use:

    * a missing directory is IOResult 2 for RmDir and MkDir but 3 for ChDir.
      fpc separates "file not found" from "path not found" by the OPERATION,
      not by the errno; both are ENOENT. A shared map cannot express it, so
      that pair is asserted together and neither row is meaningful alone.
    * a too-long name is 3 here, where the file table answers 2 for the same
      errno.

  THE OTHER LOAD-BEARING ROW IS THE EMPTY PATH. fpc's RmDir('') is a no-op
  returning 0. A naive implementation passes the empty string to the syscall
  and gets ENOENT, which is a WRONG code for a call that is supposed to do
  nothing -- and, worse, an implementation that resolved '' to the current
  directory would delete or enter it. So the no-op is asserted for its CODE and
  for its ABSENCE OF EFFECT: the sandbox must still exist and the working
  directory must be unmoved afterwards.

  And every negative row is paired with a positive one, because a stub that
  reported a plausible error for everything would satisfy the failures alone.

  This test builds its own sandbox under argv[1]. It needs a directory that is
  EMPTY (removable), one that is NOT (refuses), a plain file (refuses, and
  differently), and one it can create and remove -- test/ supplies none of
  those and would make several rows answer identically. }
program lib_dirio;

uses sysutils;

var ok, total: Integer;

procedure Chk(cond: Boolean; const what: AnsiString);
begin
  Inc(total);
  if cond then Inc(ok) else WriteLn('FAIL: ', what);
end;

procedure ChkEq(got, want: Integer; const what: AnsiString);
begin
  Inc(total);
  if got = want then Inc(ok)
  else WriteLn('FAIL: ', what, ' -- got ', got, ' want ', want);
end;

var
  base, long, cwd0, cwd1: AnsiString;
  i, r: Integer;
  fx: Text;
begin
  ok := 0; total := 0;
  base := ParamStr(1);
  if base = '' then begin WriteLn('FAIL: no sandbox path given'); Halt(1); end;

  { --- sandbox ------------------------------------------------------------ }
  ForceDirectories(base + '/full');
  ForceDirectories(base + '/empty');
  Assign(fx, base + '/full/x'); Rewrite(fx); WriteLn(fx, 'x'); Close(fx);

  long := '';
  for i := 1 to 300 do long := long + 'a';

  cwd0 := GetCurrentDir;

  {$push}{$I-}

  { --- the EMPTY PATH is a no-op returning 0, and must have NO effect ------ }
  RmDir('');
  ChkEq(IOResult, 0, 'RmDir('''') is a no-op returning 0, as in fpc');
  MkDir('');
  ChkEq(IOResult, 0, 'MkDir('''') is a no-op returning 0');
  ChDir('');
  ChkEq(IOResult, 0, 'ChDir('''') is a no-op returning 0');
  Chk(DirectoryExists(base + '/empty'),
      'the empty-path no-ops did NOT resolve to the current directory and delete it');
  Chk(GetCurrentDir = cwd0,
      'ChDir('''') did NOT move the working directory');

  { --- the ENOENT PAIR: 2 for RmDir/MkDir, 3 for ChDir -------------------- }
  RmDir(base + '/nonexistent');
  ChkEq(IOResult, 2, 'RmDir of a missing directory is 2 (file not found)');
  MkDir(base + '/no/such/parent');
  ChkEq(IOResult, 2, 'MkDir under a missing parent is 2');
  ChDir(base + '/nonexistent');
  ChkEq(IOResult, 3, 'ChDir to a missing directory is 3 (PATH not found) -- not 2');

  { --- a too-long name is 3 for all three, where the FILE table says 2 ----- }
  RmDir(base + '/' + long);
  ChkEq(IOResult, 3, 'RmDir ENAMETOOLONG is 3');
  MkDir(base + '/' + long);
  ChkEq(IOResult, 3, 'MkDir ENAMETOOLONG is 3');
  ChDir(base + '/' + long);
  ChkEq(IOResult, 3, 'ChDir ENAMETOOLONG is 3');

  { --- wrong kind, or in the way: 5 --------------------------------------- }
  RmDir(base + '/full');
  ChkEq(IOResult, 5, 'RmDir of a NON-EMPTY directory is 5');
  Chk(DirectoryExists(base + '/full'), 'and it is still there');
  RmDir(base + '/full/x');
  ChkEq(IOResult, 5, 'RmDir of a plain file is 5');
  Chk(FileExists(base + '/full/x'), 'and the file is still there');
  MkDir(base + '/empty');
  ChkEq(IOResult, 5, 'MkDir over an existing directory is 5');
  MkDir(base + '/full/x');
  ChkEq(IOResult, 5, 'MkDir over an existing file is 5');
  ChDir(base + '/full/x');
  ChkEq(IOResult, 5, 'ChDir into a plain file is 5');
  ChDir(base + '/full/x/sub');
  ChkEq(IOResult, 5, 'ChDir through a plain file is 5');

  { --- and they actually WORK, which the failures above cannot show -------- }
  MkDir(base + '/fresh');
  ChkEq(IOResult, 0, 'MkDir of a new directory succeeds');
  Chk(DirectoryExists(base + '/fresh'), 'and the directory now EXISTS');

  ChDir(base + '/fresh');
  ChkEq(IOResult, 0, 'ChDir into it succeeds');
  cwd1 := GetCurrentDir;
  Chk(cwd1 <> cwd0, 'and the working directory actually MOVED');
  Chk(Copy(cwd1, Length(cwd1) - 5, 6) = '/fresh',
      'it moved to the directory named, not to some other one');

  ChDir(cwd0);
  ChkEq(IOResult, 0, 'ChDir back succeeds');
  Chk(GetCurrentDir = cwd0, 'and it moved back');

  RmDir(base + '/fresh');
  ChkEq(IOResult, 0, 'RmDir of the now-empty directory succeeds');
  Chk(not DirectoryExists(base + '/fresh'), 'and it is GONE');

  RmDir(base + '/empty');
  ChkEq(IOResult, 0, 'RmDir of a pre-existing empty directory succeeds');

  { --- IOResult CLEARS on read, so a stale code cannot pass for a fresh one }
  RmDir(base + '/nonexistent');
  r := IOResult;
  ChkEq(r, 2, 'a fresh failure reports 2');
  ChkEq(IOResult, 0, 'and reading IOResult CLEARED it -- the second read is 0');

  {$pop}

  WriteLn('total ok ', ok, ' / ', total);
end.
