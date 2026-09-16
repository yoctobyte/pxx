{ FindFirst / FindNext / FindClose, and the DOS attribute word they report.

  THE FIXTURE BUILDS ITS OWN DIRECTORY, because the assertions are about
  attribute BITS and no checked-in tree has the entries that set them: a
  dotfile, an unwritable file, a symlink to a file, a symlink to a directory.
  Running against test/ instead would have made faAnyFile and faDirectory
  return the identical answer -- which is exactly what the first probe of this
  work did, and it looked like a passing test.

  EVERY NEGATIVE ROW IS PAIRED WITH A POSITIVE ONE IN THE SAME RUN. "`.` is not
  hidden" passes against an implementation that never sets faHidden at all, so
  it is asserted beside ".hidden.txt IS hidden"; "a writable file is not
  readonly" sits beside "the chmod'd one is". Neither half means anything
  alone.

  The attribute VALUES here were not written from the specification: this
  program was compiled under fpc and under pxx against the same directory and
  the two outputs diffed byte for byte, rows and attribute integers alike. The
  numbers below are what both compilers answer. }
program lib_findfirst;

uses sysutils, platform;

var
  ok, total: Integer;
  base: AnsiString;

procedure Chk(cond: Boolean; const what: AnsiString);
begin
  Inc(total);
  if cond then Inc(ok) else WriteLn('FAIL: ', what);
end;

procedure WriteFile_(const path, content: AnsiString);
var f: Text;
begin
  AssignFile(f, path);
  Rewrite(f);
  Write(f, content);
  CloseFile(f);
end;

{ Attributes of one named entry, via a wildcard-free FindFirst. -1 when the
  entry is not there or the filter rejects it. }
function AttrOf(const path: AnsiString; filter: LongInt): LongInt;
var sr: TSearchRec;
begin
  if FindFirst(path, filter, sr) = 0 then
  begin
    AttrOf := sr.Attr;
    FindClose(sr);
  end
  else
    AttrOf := -1;
end;

{ How many entries a mask+filter pair yields, and optionally whether one
  particular name was among them. }
function CountMatches(const mask: AnsiString; filter: LongInt;
                      const lookFor: AnsiString; var seen: Boolean): Integer;
var sr: TSearchRec; n: Integer;
begin
  n := 0;
  seen := False;
  if FindFirst(mask, filter, sr) = 0 then
  begin
    repeat
      Inc(n);
      if sr.Name = lookFor then seen := True;
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  CountMatches := n;
end;

var
  sr: TSearchRec;
  n, nAny, n3F: Integer;
  seen, seenHidden, seenPlain, seenSub: Boolean;
  a: LongInt;
  rc: Integer;
  linkTarget: AnsiString;
begin
  ok := 0; total := 0;

  base := ParamStr(1);
  if base = '' then base := '/tmp/pxx_lib_findfirst_sandbox';

  { ---- setup, and the run STOPS if it did not work ---------------------
    Every assertion below is about the contents of this directory, so a
    comparison made before it exists cannot fail and must not be attempted. }
  if DirectoryExists(base) then
  begin
    DeleteFile(base + '/plain.txt');
    DeleteFile(base + '/.hidden.txt');
    DeleteFile(base + '/readonly.txt');
    DeleteFile(base + '/link.txt');
    DeleteFile(base + '/linkdir');
    DeleteFile(base + '/dangling');
    DeleteFile(base + '/one.txt');
    RemoveDir(base + '/subdir');
    RemoveDir(base);
  end;
  Chk(CreateDir(base), 'sandbox directory could be created at ' + base);
  if not DirectoryExists(base) then
  begin
    WriteLn('PRECONDITION FAILED: no sandbox at ', base, ' -- not running the rest');
    WriteLn('total ok ', ok, ' / ', total);
    Halt(1);
  end;

  WriteFile_(base + '/plain.txt', 'abcdef');
  WriteFile_(base + '/.hidden.txt', 'hid');
  WriteFile_(base + '/readonly.txt', 'ro');
  WriteFile_(base + '/one.txt', 'x');
  Chk(CreateDir(base + '/subdir'), 'subdirectory created');
  { The targets go through a VARIABLE deliberately. `PChar(AnsiString('x'))`
    compiles and yields one garbage byte under this compiler where fpc yields
    the string -- a silently wrong value, reported separately. Using the
    ordinary spelling here is not a workaround for it; it is the spelling the
    bug report says should have been written either way. }
  linkTarget := 'plain.txt';
  rc := PalSymlink(PChar(linkTarget), PChar(base + '/link.txt'));
  Chk(rc = 0, 'symlink to a file created');
  linkTarget := 'subdir';
  rc := PalSymlink(PChar(linkTarget), PChar(base + '/linkdir'));
  Chk(rc = 0, 'symlink to a directory created');
  linkTarget := 'nothing-is-here';
  rc := PalSymlink(PChar(linkTarget), PChar(base + '/dangling'));
  Chk(rc = 0, 'dangling symlink created');
  rc := PalChmod(PChar(base + '/readonly.txt'), &444);
  Chk(rc = 0, 'readonly.txt made unwritable');

  { ---- the entries are all there --------------------------------------- }
  nAny := CountMatches(base + '/' + AllFilesMask, faAnyFile, 'plain.txt', seenPlain);
  { NINE, not ten: the dangling link is created but must NOT come back, which
    is the row below. Counting it here would have hidden that. }
  Chk(nAny = 9, 'faAnyFile returns the nine RESOLVABLE entries (got ' + IntToStr(nAny) + ')');
  Chk(seenPlain, 'plain.txt is among them');

  { `.` and `..` ARE returned -- fpc returns them and fpc''s own cfileutl.pas
    filters them out by hand, which is only necessary because they arrive. }
  n := CountMatches(base + '/' + AllFilesMask, faAnyFile, '.', seen);
  Chk(seen, 'the `.` entry is returned, not silently skipped');
  n := CountMatches(base + '/' + AllFilesMask, faAnyFile, '..', seen);
  Chk(seen, 'the `..` entry is returned, not silently skipped');

  { A link whose target does not exist is SKIPPED when the search follows
    links, because the stat fails -- fpc does the same, and it is why the
    entry count above is nine and not ten. Asked for with faSymLink it comes
    back, because lstat succeeds on the link itself. }
  n := CountMatches(base + '/' + AllFilesMask, faAnyFile, 'dangling', seen);
  Chk(not seen, 'a dangling symlink is skipped when the search follows links');
  n := CountMatches(base + '/' + AllFilesMask, faAnyFile or faSymLink, 'dangling', seen);
  Chk(seen, 'and it IS returned when faSymLink is requested');

  { ---- the attribute bits, each negative paired with a positive --------- }
  a := AttrOf(base + '/plain.txt', faAnyFile);
  Chk(a >= 0, 'a plain file is found by exact path');
  Chk((a and faArchive) <> 0, 'every unix entry carries faArchive');
  Chk((a and faDirectory) = 0, 'a plain file is not a directory');
  Chk((a and faReadOnly) = 0, 'a writable file is not readonly');
  Chk((a and faHidden) = 0, 'plain.txt is not hidden');

  a := AttrOf(base + '/.hidden.txt', faAnyFile);
  Chk((a and faHidden) <> 0, 'a leading dot sets faHidden');

  a := AttrOf(base + '/readonly.txt', faAnyFile);
  Chk((a and faReadOnly) <> 0, 'an unwritable file sets faReadOnly');

  a := AttrOf(base + '/subdir', faAnyFile);
  Chk((a and faDirectory) <> 0, 'a directory sets faDirectory');

  { `.` and `..` must NOT be hidden even though they begin with a dot -- that
    is the whole point of fpc''s second-character test, and an implementation
    that checks only the first character gets this wrong while passing every
    row above. }
  seenHidden := False;
  if FindFirst(base + '/' + AllFilesMask, faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name = '.') or (sr.Name = '..') then
        if (sr.Attr and faHidden) <> 0 then seenHidden := True;
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  Chk(not seenHidden, '`.` and `..` are NOT faHidden despite the leading dot');

  { ---- symlinks: reported as the TARGET unless faSymLink was asked for --- }
  a := AttrOf(base + '/link.txt', faAnyFile);
  Chk((a and faSymLink) = 0, 'without faSymLink a link reports its target, not itself');
  a := AttrOf(base + '/link.txt', faAnyFile or faSymLink);
  Chk((a and faSymLink) <> 0, 'with faSymLink requested the link reports faSymLink');
  a := AttrOf(base + '/linkdir', faAnyFile or faSymLink);
  Chk((a and faSymLink) <> 0, 'a link to a directory reports faSymLink');
  Chk((a and faDirectory) <> 0, 'a link to a directory ALSO reports faDirectory');

  { ---- the filter is permissive, not a requirement ---------------------- }
  n := CountMatches(base + '/' + AllFilesMask, faDirectory, 'plain.txt', seenPlain);
  Chk(seenPlain, 'faDirectory still returns ORDINARY files -- Attr only ADDS types');
  n := CountMatches(base + '/' + AllFilesMask, faDirectory, '.hidden.txt', seenHidden);
  Chk(not seenHidden, 'faDirectory excludes the hidden file, because faHidden was not asked for');
  n := CountMatches(base + '/' + AllFilesMask, faDirectory, 'subdir', seenSub);
  Chk(seenSub, 'faDirectory includes the directory');

  { $3F is the widely-quoted spelling of faAnyFile and is NOT fpc''s $1FF.
    Measured: on unix the two select the same entries, because faNormal is
    never set and faSymLink only appears when it was requested anyway. }
  n3F := CountMatches(base + '/' + AllFilesMask, $3F, '', seen);
  Chk(n3F = nAny, '$3F and faAnyFile select the same entries on unix');
  Chk(faAnyFile = $1FF, 'faAnyFile carries fpc value $1FF');

  { ---- masks ------------------------------------------------------------ }
  { FIVE: plain.txt, .hidden.txt, readonly.txt, one.txt AND link.txt -- the
    symlink's own name ends in .txt too. Written as 4 first, from counting the
    regular files and forgetting the link. }
  n := CountMatches(base + '/*.txt', faAnyFile, '', seen);
  Chk(n = 5, '*.txt matches all five .txt entries, link included (got ' + IntToStr(n) + ')');
  n := CountMatches(base + '/?ne.txt', faAnyFile, 'one.txt', seen);
  Chk(seen and (n = 1), '? matches exactly one character');
  n := CountMatches(base + '/*dir*', faAnyFile, '', seen);
  Chk(n = 2, 'a mask with a leading AND trailing star matches subdir and linkdir');
  n := CountMatches(base + '/nomatch*', faAnyFile, '', seen);
  Chk(n = 0, 'a mask that matches nothing returns nothing');

  { ---- the no-wildcard path is a different route and must also work ------ }
  Chk(FindFirst(base + '/plain.txt', faAnyFile, sr) = 0, 'exact path with no wildcard is found');
  Chk(sr.Name = 'plain.txt', 'the exact-path hit reports the BASE name, not the whole path');
  Chk(sr.Size = 6, 'size is the real byte count');
  Chk(sr.Time > 1600000000, 'time is a plausible recent epoch second');
  Chk(FindNext(sr) <> 0, 'a wildcard-free search has exactly one result');
  FindClose(sr);

  Chk(FindFirst(base + '/nosuch', faAnyFile, sr) <> 0, 'a missing exact path is not found');
  FindClose(sr);   { must be safe on a FindFirst that FAILED }
  Chk(True, 'FindClose on a failed FindFirst does not crash');

  { A char device is the only faSysFile this fixture can reach -- it cannot
    mkfifo -- and /dev/null is one on every target this runs on. }
  a := AttrOf('/dev/null', faAnyFile);
  if a >= 0 then
    Chk((a and faSysFile) <> 0, '/dev/null reports faSysFile')
  else
    Chk(False, '/dev/null could be stat''d at all');

  { Exhaustion is sticky: FindNext past the end stays failed rather than
    rewinding, so a caller''s loop cannot silently run twice. }
  if FindFirst(base + '/one.txt', faAnyFile, sr) = 0 then
  begin
    Chk(FindNext(sr) <> 0, 'first FindNext past the end fails');
    Chk(FindNext(sr) <> 0, 'and it STAYS failed rather than rewinding');
    FindClose(sr);
  end
  else
    Chk(False, 'one.txt was found so exhaustion could be tested');

  WriteLn('total ok ', ok, ' / ', total);
end.
