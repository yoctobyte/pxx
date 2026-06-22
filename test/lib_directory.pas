program lib_directory;

uses sysutils, platform, platform_types;

var
  list: TFileInfoArray;
  fd, i, alphaIdx, childIdx: Integer;
  b: Byte;
  stat: TPalFileStat;

function FindEntry(const name: AnsiString): Integer;
var j: Integer;
begin
  Result := -1;
  for j := 0 to Length(list) - 1 do
    if list[j].Name = name then
    begin
      Result := j;
      Exit;
    end;
end;

begin
  PalDelete(PChar('/tmp/pxx_dir_suite/alpha.txt'));
  PalRmdir(PChar('/tmp/pxx_dir_suite/child'));
  PalRmdir(PChar('/tmp/pxx_dir_suite'));

  writeln('mkdir=', PalMkdir(PChar('/tmp/pxx_dir_suite'), 493));
  writeln('child=', PalMkdir(PChar('/tmp/pxx_dir_suite/child'), 493));
  fd := PalOpen(PChar('/tmp/pxx_dir_suite/alpha.txt'),
    PAL_OPEN_WRITE or PAL_OPEN_CREATE or PAL_OPEN_TRUNC, 438);
  if fd >= 0 then
  begin
    b := Ord('x');
    i := Integer(PalWrite(fd, @b, 1));
    fd := PalClose(fd);
  end;

  if GetDirectoryContents('/tmp/pxx_dir_suite', list) then
    writeln('list=ok')
  else
    writeln('list=fail');

  alphaIdx := FindEntry('alpha.txt');
  childIdx := FindEntry('child');

  if alphaIdx >= 0 then writeln('alpha=1') else writeln('alpha=0');
  if childIdx >= 0 then writeln('child=1') else writeln('child=0');
  if (alphaIdx >= 0) and (not list[alphaIdx].IsDir) then writeln('alpha-file=1') else writeln('alpha-file=0');
  if (childIdx >= 0) and list[childIdx].IsDir then writeln('child-dir=1') else writeln('child-dir=0');
  if (alphaIdx >= 0) and (list[alphaIdx].Size = 1) then writeln('alpha-size=1') else writeln('alpha-size=0');
  if (PalStat(PChar('/tmp/pxx_dir_suite/alpha.txt'), stat) >= 0) and stat.IsFile and (stat.Size = 1) then
    writeln('stat-file=1')
  else
    writeln('stat-file=0');
  if (PalStat(PChar('/tmp/pxx_dir_suite/child'), stat) >= 0) and stat.IsDir then
    writeln('stat-dir=1')
  else
    writeln('stat-dir=0');

  PalDelete(PChar('/tmp/pxx_dir_suite/alpha.txt'));
  PalRmdir(PChar('/tmp/pxx_dir_suite/child'));
  PalRmdir(PChar('/tmp/pxx_dir_suite'));
end.
