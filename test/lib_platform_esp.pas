program lib_platform_esp;

{ Asserts the ESP PAL's UNSUPPORTED surface: every entry point below must
  refuse (-38 = PAL_ERR_UNSUPPORTED) rather than answer wrongly.

  Every fd argument is BADFD (-1), never 0. fd 0 is stdin, so the old spelling
  measured the launch environment instead of the PAL: `PalSocketClose(0)` closed
  the test's own stdin, and with stdin already closed the test's `PalSocket()`
  was handed descriptor 0 back, so every later call silently operated on a real
  socket. Four stdin kinds gave four different outputs from one binary.
  ([[bug-b-two-lib-tests-are-environment-dependent-by-construction]])

  The socket the test does create is closed again, and reported as ok/its error
  rather than as its number, which is likewise an environment fact. }

uses platform;

const
  BADFD = -1;   { never a live descriptor — the answer is about the PAL }

var
  peerAddr: LongWord;
  peerPort: Integer;
  sock: Integer;

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
  writeln('read=', Integer(PalRead(BADFD, nil, 0)));
  writeln('seek=', Integer(PalSeek(BADFD, 0, PAL_SEEK_SET)));
  writeln('flush=', PalFlush(BADFD));
  writeln('delete=', PalDelete(PChar('/tmp/no-host-fallback')));
  writeln('rename=', PalRename(PChar('/tmp/no-host-fallback'),
    PChar('/tmp/no-host-fallback-2')));
  writeln('mkdir=', PalMkdir(PChar('/tmp/no-host-fallback-dir'), 493));
  writeln('rmdir=', PalRmdir(PChar('/tmp/no-host-fallback-dir')));
  { The one call that may legitimately succeed. Its descriptor NUMBER is an
    environment fact (it is whatever is free), so report ok and hand it back. }
  sock := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  if sock >= 0 then
  begin
    writeln('socket=ok');
    PalSocketClose(sock);
  end
  else
    writeln('socket=', sock);
  writeln('reuse=', PalSetSocketReuseAddr(BADFD, 1));
  writeln('nonblock=', PalSetSocketNonBlocking(BADFD, 1));
  writeln('bind=', PalBindIpv4(BADFD, PAL_NET_IP_LOOPBACK, 48691));
  writeln('connect=', PalConnectIpv4(BADFD, PAL_NET_IP_LOOPBACK, 48691));
  writeln('listen=', PalListen(BADFD, 1));
  writeln('accept=', PalAccept(BADFD));
  writeln('recv=', Integer(PalRecv(BADFD, nil, 0)));
  writeln('send=', Integer(PalSend(BADFD, nil, 0)));
  writeln('shutdown=', PalShutdown(BADFD, PAL_SHUT_RDWR));
  writeln('sockclose=', PalSocketClose(BADFD));
  writeln('sendto=', Integer(PalSendToIpv4(BADFD, nil, 0, PAL_NET_IP_LOOPBACK, 48691)));
  writeln('recvfrom=', Integer(PalRecvFromIpv4(BADFD, nil, 0, peerAddr, peerPort)));
  writeln('poll=', PalPoll(BADFD, PAL_POLL_IN, 0));
  writeln('sockerr=', PalGetSockError(BADFD));
  writeln('sockname=', PalGetSockNameIpv4(BADFD, peerAddr, peerPort));
  writeln('acceptip=', PalAcceptIpv4(BADFD, peerAddr, peerPort));
  writeln('unsupported=', PalUnsupported);
end.
