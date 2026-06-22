program lib_platform_esp;

uses platform;

var
  peerAddr: LongWord;
  peerPort: Integer;

begin
  peerAddr := 0;
  peerPort := 0;
  if PalPlatform = PAL_PLATFORM_POSIX then writeln('posix');
  if PalPlatform = PAL_PLATFORM_ESP_IDF then writeln('esp-idf');
  if PalHasFiles then writeln('files');
  if PalHasSockets then writeln('sockets');
  if PalHasThreads then writeln('threads');
  if PalHasDynlib then writeln('dynlib');
  writeln('open=', PalOpen(PChar('/tmp/no-host-fallback'), PAL_OPEN_READ, 0));
  writeln('read=', Integer(PalRead(0, nil, 0)));
  writeln('seek=', Integer(PalSeek(0, 0, PAL_SEEK_SET)));
  writeln('flush=', PalFlush(0));
  writeln('delete=', PalDelete(PChar('/tmp/no-host-fallback')));
  writeln('rename=', PalRename(PChar('/tmp/no-host-fallback'),
    PChar('/tmp/no-host-fallback-2')));
  writeln('mkdir=', PalMkdir(PChar('/tmp/no-host-fallback-dir'), 493));
  writeln('rmdir=', PalRmdir(PChar('/tmp/no-host-fallback-dir')));
  writeln('socket=', PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0));
  writeln('reuse=', PalSetSocketReuseAddr(0, 1));
  writeln('nonblock=', PalSetSocketNonBlocking(0, 1));
  writeln('bind=', PalBindIpv4(0, PAL_NET_IP_LOOPBACK, 48691));
  writeln('connect=', PalConnectIpv4(0, PAL_NET_IP_LOOPBACK, 48691));
  writeln('listen=', PalListen(0, 1));
  writeln('accept=', PalAccept(0));
  writeln('recv=', Integer(PalRecv(0, nil, 0)));
  writeln('send=', Integer(PalSend(0, nil, 0)));
  writeln('shutdown=', PalShutdown(0, PAL_SHUT_RDWR));
  writeln('sockclose=', PalSocketClose(0));
  writeln('sendto=', Integer(PalSendToIpv4(0, nil, 0, PAL_NET_IP_LOOPBACK, 48691)));
  writeln('recvfrom=', Integer(PalRecvFromIpv4(0, nil, 0, peerAddr, peerPort)));
  writeln('poll=', PalPoll(0, PAL_POLL_IN, 0));
  writeln('unsupported=', PalUnsupported);
end.
