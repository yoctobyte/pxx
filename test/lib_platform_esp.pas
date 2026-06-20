program lib_platform_esp;

uses platform;

begin
  if PalPlatform = PAL_PLATFORM_POSIX then writeln('posix');
  if PalPlatform = PAL_PLATFORM_ESP_IDF then writeln('esp-idf');
  if PalHasFiles then writeln('files');
  if PalHasSockets then writeln('sockets');
  if PalHasThreads then writeln('threads');
  if PalHasDynlib then writeln('dynlib');
  writeln('read=', Integer(PalRead(0, nil, 0)));
  writeln('unsupported=', PalUnsupported);
end.
