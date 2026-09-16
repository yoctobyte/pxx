{ GetDir and the path-separator constants.

  THE LOAD-BEARING ROWS ARE THE TWO THAT A CONSTANT WOULD FAIL. "GetDir returns
  a non-empty absolute path with no trailing separator" is true of a function
  that returns one hardcoded string and never looks at the process, so it is
  asserted beside a row that CHANGES the working directory and requires GetDir
  to follow -- and beside one that pre-fills the var parameter with a sentinel
  and requires it to be overwritten.

  The values were checked against fpc rather than written from the
  specification: the same probe compiled under both, run from one directory,
  diffs byte for byte across eight rows, and the harness was made to redden on
  a deliberately wrong separator set before that green was believed. }
program lib_getdir;

uses sysutils;

var ok, total: Integer;

procedure Chk(cond: Boolean; const what: AnsiString);
begin
  Inc(total);
  if cond then Inc(ok) else WriteLn('FAIL: ', what);
end;

var
  d, d0, d3, cur, sub: AnsiString;
begin
  ok := 0; total := 0;

  GetDir(0, d);
  Chk(d <> '', 'GetDir writes something');
  Chk((Length(d) > 0) and (d[1] in AllowDirectorySeparators), 'the path is absolute');
  Chk((Length(d) > 0) and (d[Length(d)] <> DirectorySeparator),
      'no trailing separator -- measured against fpc, which does not add one');
  Chk(d = GetCurrentDir, 'GetDir agrees with GetCurrentDir');

  { DriveNr is accepted and ignored on unix. fpc answers the cwd for any value;
    refusing a non-zero drive would reject code fpc accepts. }
  GetDir(0, d0);
  GetDir(3, d3);
  Chk(d0 = d3, 'DriveNr is ignored, not validated');

  { THE VAR PARAMETER IS WRITTEN. A GetDir that quietly did nothing would leave
    the sentinel, and every row above would still pass. }
  d := 'SENTINEL-NOT-OVERWRITTEN';
  GetDir(0, d);
  Chk(d <> 'SENTINEL-NOT-OVERWRITTEN', 'the var parameter is actually assigned');

  { AND IT READS THE PROCESS, not a cached or hardcoded value: move the working
    directory and require GetDir to follow, then move back and require it to
    follow again. This is the row a constant cannot pass. }
  cur := GetCurrentDir;
  sub := cur + DirectorySeparator + 'test';
  if DirectoryExists(sub) and SetCurrentDir(sub) then
  begin
    GetDir(0, d);
    Chk(d = sub, 'GetDir follows the working directory when it CHANGES');
    Chk(d <> cur, 'and it no longer reports the old one');
    Chk(SetCurrentDir(cur), 'the working directory could be restored');
    GetDir(0, d);
    Chk(d = cur, 'GetDir follows it BACK');
  end
  else
  begin
    { Branch on the precondition rather than comparing against a directory the
      process never entered -- a comparison whose setup failed cannot fail. }
    Chk(False, 'could enter ' + sub + ' to test that GetDir tracks the cwd');
    Chk(False, '(dependent row not run)');
    Chk(False, '(dependent row not run)');
    Chk(False, '(dependent row not run)');
  end;

  { ---- the separator constants, fpc sysunixh.inc:31-36 ------------------- }
  Chk(DirectorySeparator = '/', 'DirectorySeparator is /');
  Chk('/' in AllowDirectorySeparators, 'forward slash is a separator');
  { THE SURPRISE, AND IT IS FPC'S: backslash is in this set ON UNIX. fpc accepts
    either byte when TESTING a path while only ever WRITING '/'. A
    reimplementation that "corrects" this to ['/'] changes how every caller
    classifies a Windows-shaped path, silently. }
  Chk('\' in AllowDirectorySeparators, 'BACKSLASH is also a separator on unix -- fpc says so');
  Chk(not ('x' in AllowDirectorySeparators), 'an ordinary character is not');
  Chk(not ('/' in AllowDriveSeparators), 'AllowDriveSeparators is empty -- no drive letters on unix');
  Chk(not ('C' in AllowDriveSeparators), 'and a drive letter is not in it either');

  { ---- the rest of fpc's sysunixh.inc const block ----------------------
    Added as a GROUP after the first version of this change shipped only the
    two names the corpus wall sat on, and the corpus answered with
    DriveSeparator as the next head 178 lines down the same file. }

  { AN EMPTY STRING, not a character -- and the row that matters is what it
    DOES: Pos(DriveSeparator, s) is real fpc code (cfileutl.pas:696) and must
    answer 0, which is how a drive-letter scan finds nothing on a platform
    with no drives. Asserting only Length = 0 would pass for a constant that
    Pos then choked on. }
  Chk(Length(DriveSeparator) = 0, 'DriveSeparator is EMPTY on unix, not a character');
  Chk(Pos(DriveSeparator, 'C:/x/y.pas') = 0, 'and Pos over it finds nothing, as fpc answers');
  Chk(ExtensionSeparator = '.', 'ExtensionSeparator is .');
  Chk(PathSeparator = ':', 'PathSeparator is : -- the PATH list separator, not a path separator');
  Chk(LFNSupport, 'LFNSupport is true');
  Chk(maxExitCode = 255, 'maxExitCode is 255');
  Chk(MaxPathLen = 4096, 'MaxPathLen is 4096 on Linux (the BSDs are 1024 -- this tracks the kernel)');
  Chk(UnusedHandle = -1, 'UnusedHandle is -1');
  Chk(FileNameCaseSensitive, 'FileNameCaseSensitive defaults true on unix');
  Chk(FileNameCasePreserving, 'FileNameCasePreserving defaults true on unix');
  { Typed constants, so a program may ASSIGN them to describe a mounted
    filesystem that differs from the platform default. If these were plain
    `const` the assignment would not compile, and every row above would still
    pass -- so the writability is asserted, and restored. }
  FileNameCaseSensitive := False;
  Chk(not FileNameCaseSensitive, 'FileNameCaseSensitive is WRITABLE, as it is in fpc');
  FileNameCaseSensitive := True;

  WriteLn('total ok ', ok, ' / ', total);
end.
