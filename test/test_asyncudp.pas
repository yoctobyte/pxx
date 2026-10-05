program test_asyncudp;
{ asyncnet's UDP and TcpListenAddr, for museum_landkaart's captive portal
  (a catch-all DNS responder on UDP, an HTTP server on every interface of a
  soft-AP). The responder parks in UdpRecvFrom before any datagram exists, so
  the reactor's read wait is exercised; it answers each query with a prefix
  to the sender's own address and port. Then a TCP listener on
  PAL_NET_IP_ANY is reached through loopback. Run under the epoll reactor
  and under -dPXX_SCHED_PAL_REACTOR (what ESP runs): same output. }
uses scheduler, asyncnet, platform;

var
  ufd, uport, lfd, lport: Integer;

procedure Responder(arg: Pointer);
var buf: array[0..63] of Byte; n: Int64; host: LongWord; port, i, k: Integer;
    reply: array[0..63] of Byte;
begin
  for k := 1 to 3 do
  begin
    n := UdpRecvFrom(ufd, @buf[0], 64, host, port);
    reply[0] := Ord('A'); reply[1] := Ord(':');
    for i := 0 to n - 1 do reply[i + 2] := buf[i];
    UdpSendTo(ufd, @reply[0], n + 2, host, port);
  end;
  writeln('responder done');
end;

procedure Client(arg: Pointer);
var c: Integer; q: AnsiString; buf: array[0..63] of Byte; n: Int64;
    host: LongWord; port, i, k: Integer; s: AnsiString;
begin
  c := UdpBind(PAL_NET_IP_LOOPBACK, 0);
  for k := 1 to 3 do
  begin
    q := 'q' + Chr(Ord('0') + k);
    UdpSendTo(c, @q[1], Length(q), PAL_NET_IP_LOOPBACK, uport);
    n := UdpRecvFrom(c, @buf[0], 64, host, port);
    s := '';
    for i := 0 to n - 1 do s := s + Chr(buf[i]);
    writeln('reply ', s, ' from-responder ', port = uport);
  end;
  TcpClose(c);
end;

procedure Acceptor(arg: Pointer);
var a: Integer; buf: array[0..7] of Byte; n: Int64;
begin
  a := TcpAccept(lfd);
  n := TcpRecv(a, @buf[0], 8);
  writeln('tcp any got ', n, ' bytes');
  TcpClose(a);
end;

procedure Dialer(arg: Pointer);
var c: Integer; m: AnsiString;
begin
  CoSleep(20);
  c := TcpConnect(lport);
  m := 'hi';
  TcpSend(c, @m[1], 2);
  TcpClose(c);
end;

begin
  ufd := UdpBind(PAL_NET_IP_ANY, 0);
  uport := TcpLocalPort(ufd);
  writeln('udp bound ', (ufd >= 0) and (uport > 0));
  Spawn(@Responder, nil);
  Spawn(@Client, nil);
  RunUntilDone;
  TcpClose(ufd);
  lfd := TcpListenAddr(PAL_NET_IP_ANY, 0);
  lport := TcpLocalPort(lfd);
  writeln('tcp any listening ', (lfd >= 0) and (lport > 0));
  Spawn(@Acceptor, nil);
  Spawn(@Dialer, nil);
  RunUntilDone;
  TcpClose(lfd);
  writeln('done');
end.
