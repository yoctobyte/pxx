program lib_platform;

uses platform;

var
  msg: array[0..2] of Byte;
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
  writeln('unsupported=', PalUnsupported);
end.
