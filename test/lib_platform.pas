program lib_platform;

uses platform;

var
  msg: array[0..2] of Byte;
  data: array[0..1] of Byte;
  fd: Integer;
  n: Int64;

begin
  if PalPlatform = PAL_PLATFORM_POSIX then writeln('posix');
  if PalPlatform = PAL_PLATFORM_ESP_IDF then writeln('esp-idf');
  if PalHasFiles then writeln('files');
  if PalHasSockets then writeln('sockets');
  if PalHasThreads then writeln('threads');
  if PalHasDynlib then writeln('dynlib');
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
    fd := PalClose(fd);
  end;
  fd := PalOpen(PChar('/tmp/pxx_pal_platform.txt'), PAL_OPEN_READ, 0);
  if fd >= 0 then
  begin
    data[0] := 0;
    data[1] := 0;
    n := PalRead(fd, @data[0], 2);
    fd := PalClose(fd);
    writeln('file=', Chr(data[0]), Chr(data[1]), ':', Integer(n));
  end;
  writeln('unsupported=', PalUnsupported);
end.
