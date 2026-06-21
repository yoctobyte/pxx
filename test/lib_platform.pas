program lib_platform;

uses platform;

var
  msg: array[0..2] of Byte;
  data: array[0..1] of Byte;
  fd: Integer;
  n: Int64;
  rc: Integer;
  size: Int64;

begin
  if PalPlatform = PAL_PLATFORM_POSIX then writeln('posix');
  if PalPlatform = PAL_PLATFORM_ESP_IDF then writeln('esp-idf');
  if PalHasFiles then writeln('files');
  if PalHasSockets then writeln('sockets');
  if PalHasThreads then writeln('threads');
  if PalHasDynlib then writeln('dynlib');
  PalDelete(PChar('/tmp/pxx_pal_platform.txt'));
  PalDelete(PChar('/tmp/pxx_pal_platform_renamed.txt'));
  PalRmdir(PChar('/tmp/pxx_pal_platform_dir'));
  msg[0] := Ord('p');
  msg[1] := Ord('a');
  msg[2] := Ord('l');
  n := PalWrite(PAL_STDOUT, @msg[0], 3);
  writeln('-write=', Integer(n));
  fd := PalOpen(PChar('/tmp/pxx_pal_platform.txt'),
    PAL_OPEN_WRITE or PAL_OPEN_CREATE or PAL_OPEN_TRUNC, 438);
  data[0] := Ord('i');
  data[1] := Ord('o');
  if fd >= 0 then
  begin
    n := PalWrite(fd, @data[0], 2);
    rc := PalFlush(fd);
    writeln('flush=', rc);
    writeln('tell=', Integer(PalTell(fd)));
    fd := PalClose(fd);
  end;
  fd := PalOpen(PChar('/tmp/pxx_pal_platform.txt'), PAL_OPEN_READ, 0);
  if fd >= 0 then
  begin
    size := PalSeek(fd, 0, PAL_SEEK_END);
    n := PalSeek(fd, 0, PAL_SEEK_SET);
    data[0] := 0;
    data[1] := 0;
    n := PalRead(fd, @data[0], 2);
    fd := PalClose(fd);
    writeln('file=', Chr(data[0]), Chr(data[1]), ':', Integer(n), ':', Integer(size));
  end;
  writeln('rename=', PalRename(PChar('/tmp/pxx_pal_platform.txt'),
    PChar('/tmp/pxx_pal_platform_renamed.txt')));
  fd := PalOpen(PChar('/tmp/pxx_pal_platform.txt'), PAL_OPEN_READ, 0);
  if fd < 0 then writeln('old-missing');
  fd := PalOpen(PChar('/tmp/pxx_pal_platform_renamed.txt'), PAL_OPEN_READ, 0);
  if fd >= 0 then
  begin
    fd := PalClose(fd);
    writeln('new-readable');
  end;
  writeln('delete=', PalDelete(PChar('/tmp/pxx_pal_platform_renamed.txt')));
  writeln('mkdir=', PalMkdir(PChar('/tmp/pxx_pal_platform_dir'), 493));
  writeln('rmdir=', PalRmdir(PChar('/tmp/pxx_pal_platform_dir')));
  writeln('unsupported=', PalUnsupported);
end.
