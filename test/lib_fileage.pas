{ SysUtils.FileAge and the epoch<->TDateTime converters.

  FileAge is the head of umbrella-pxx-compiles-fpc-itself: FPC's comphook.pas:474
  is `Result := FileAge(F)` inside def_GetNamedFileTime, and we had FileGetDate
  (by open HANDLE) but nothing by PATH.

  TWO THINGS HERE ARE NOT THE OBVIOUS ONES.

  1. THE DIRECTORY ROW. FPC returns -1 for a directory, not its mtime --
     rtl/unix/sysutils.pp, `if (fpstat(...)<0) or fpS_ISDIR(info.st_mode) then
     exit(-1)`. Read out of its source, not assumed. A directory HAS an mtime,
     so this is a case where the obvious implementation silently disagrees.

  2. -1 IS ALSO WHAT A BROKEN FileAge WOULD RETURN FOR EVERYTHING. So the two
     rows that expect -1 cannot stand alone: the row above them, a real file
     answering a real timestamp, is what makes them mean anything. Both are
     asserted in the same run for that reason.

  THE CROSS-CHECK IS THE STRONGEST ROW. FileAge(path) and FileGetDate(handle)
  reach the same kernel field by two different syscalls -- stat by name, fstat
  by descriptor. (The handle comes from PalOpen rather than SysUtils.FileOpen
  because SysUtils.FileOpen/FileClose do not exist here yet either -- a
  neighbouring gap, noted rather than widened into this change. The Text route
  uses public RTL surface and no magic open flags.) They must agree to the second on the same file, and nothing in
  either implementation forces that: they were written a year apart and share no
  code. Two doors that FAIL DIFFERENTLY is the only kind of corroboration worth
  having.

  UTC IS DELIBERATE and diverges from FPC's FileDateToDateTime, which applies
  the local timezone via EpochToLocal. We have no timezone database and Now and
  GetLocalTime are already UTC; ours matches FPC's FileDateToUniversal. The
  property real code depends on is that `FileDateToDateTime(FileAge(f)) < Now`
  is true when the file is older than now, and that holds BECAUSE both sides use
  one clock. Matching FPC on just this function would break the pair. }
program lib_fileage;

uses sysutils, textfile;

var
  ok, total: LongInt;

procedure Chk(cond: Boolean; const what: string);
begin
  total := total + 1;
  if cond then ok := ok + 1
  else WriteLn('FAIL: ', what);
end;

var
  age, viaHandle, rt: Int64;
  h: Integer;
  tf: Text;
  dt: TDateTime;
  fn: string;
begin
  ok := 0; total := 0;

  { a file that certainly exists: this test's own source }
  fn := 'test/lib_fileage.pas';

  age := FileAge(fn);
  Chk(age > 0, 'FileAge of an existing file is a real timestamp');
  Chk(age > 1600000000, 'that timestamp is after 2020 (a plausible mtime)');

  { the cross-check: stat-by-name against fstat-by-descriptor }
  AssignFile(tf, fn);
  Reset(tf);
  h := tf.Handle;
  { ASSERT THE PRECONDITION, AND BRANCH ON IT. A comparison whose inputs were
    never proven to exist cannot fail: if the open silently did not happen,
    FileGetDate(-1) is -1 and so is a broken FileAge, and the cross-check would
    PASS by agreeing about nothing. }
  Chk(h > 2, 'the file opened on a real descriptor');
  if h > 2 then
  begin
    viaHandle := FileGetDate(h);
    Chk(viaHandle > 0, 'FileGetDate returned a real timestamp too');
    Chk(viaHandle = age, 'FileAge(path) agrees with FileGetDate(handle)');
  end
  else
  begin
    Chk(False, 'FileGetDate returned a real timestamp too -- NOT RUN');
    Chk(False, 'FileAge(path) agrees with FileGetDate(handle) -- NOT RUN');
  end;
  CloseFile(tf);

  { the two -1 rows, meaningful only because the rows above are not -1 }
  Chk(FileAge('/tmp') = -1, 'a DIRECTORY is -1, not its mtime');
  Chk(FileAge('no/such/path/at/all') = -1, 'a missing path is -1');
  Chk(age <> -1, 'and the real file was NOT -1 in the same run');

  { the converters round-trip, on both sides of the epoch }
  rt := DateTimeToFileDate(FileDateToDateTime(age));
  Chk(rt = age, 'epoch -> TDateTime -> epoch round-trips');
  rt := DateTimeToFileDate(FileDateToDateTime(0));
  Chk(rt = 0, 'the epoch itself round-trips');
  rt := DateTimeToFileDate(FileDateToDateTime(-86400));
  Chk(rt = -86400, 'a PRE-epoch value round-trips (Round, not Trunc)');
  rt := DateTimeToFileDate(FileDateToDateTime(-1));
  Chk(rt = -1, 'one second before the epoch round-trips');

  { anchors with a known answer, so a broken conversion cannot pass by being
    self-consistent -- a round trip alone would survive any linear error }
  Chk(FileDateToDateTime(0) = 25569.0, 'the Unix epoch is TDateTime 25569');
  Chk(FormatDateTime('yyyy-mm-dd', FileDateToDateTime(0)) = '1970-01-01',
      'and it formats as 1970-01-01');
  Chk(FormatDateTime('yyyy-mm-dd hh:nn:ss', FileDateToDateTime(1000000000)) =
      '2001-09-09 01:46:40', '1e9 seconds is 2001-09-09 01:46:40 UTC');

  { the consistency that actually matters to a caller }
  dt := FileDateToDateTime(age);
  Chk(dt < Now, 'the file is older than Now, on one clock');
  Chk(dt > EncodeDate(2020, 1, 1), 'and newer than 2020');

  WriteLn('total ok ', ok, ' / ', total);
end.
