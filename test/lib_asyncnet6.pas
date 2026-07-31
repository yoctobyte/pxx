program lib_asyncnet6;
{ asyncnet over IPv6 (feature-ipv6-complete-surface): a server coroutine and a
  client coroutine on ONE thread, both parked on the epoll reactor, talking
  over ::1. The point is that the reactor half is family-agnostic — only the
  socket-creating calls come in pairs — so this exercises TcpListen6 /
  TcpConnect6 against the SAME TcpAccept/TcpRecv/TcpSend the v4 tests use.

  SKIPs when the host has no AF_INET6, like lib_ipv6 and lib_net6: a kernel
  with IPv6 turned off is not a code defect. }
uses scheduler, asyncnet, platform;

const PORT = 28860;

var
  gGot:        AnsiString;
  gEcho:       AnsiString;
  gServerDone: Boolean;
  gListenFd:   Integer;

procedure ServerCo(arg: Pointer);
var cfd: Integer; buf: array[0..255] of Byte; n: Int64; i: Integer; resp: AnsiString;
begin
  cfd := TcpAccept(gListenFd);            { yields until the client connects }
  n := TcpRecv(cfd, @buf[0], 256);
  gGot := '';
  for i := 0 to Integer(n) - 1 do gGot := gGot + Chr(buf[i]);
  resp := 'pong6';
  TcpSend(cfd, @resp[1], Length(resp));
  TcpClose(cfd);
  TcpClose(gListenFd);
  gServerDone := True;
end;

procedure ClientCo(arg: Pointer);
var fd: Integer; buf: array[0..255] of Byte; n: Int64; i: Integer; req: AnsiString;
begin
  fd := TcpConnect6(PORT);
  req := 'ping6';
  TcpSend(fd, @req[1], Length(req));
  n := TcpRecv(fd, @buf[0], 256);
  gEcho := '';
  for i := 0 to Integer(n) - 1 do gEcho := gEcho + Chr(buf[i]);
  TcpClose(fd);
end;

begin
  { listen BEFORE the client coroutine can run, so the connect cannot lose the
    race; the accept itself still parks on the reactor }
  gListenFd := TcpListen6(PORT);
  if gListenFd < 0 then
  begin
    writeln('ASYNCNET6 SKIP (no AF_INET6 on this host, listen = ', gListenFd, ')');
    Halt(0);
  end;
  gServerDone := False;
  Spawn(@ServerCo, nil);
  Spawn(@ClientCo, nil);
  RunUntilDone;                           { the reactor drives both to completion }
  if gGot <> 'ping6' then begin writeln('FAIL server got [', gGot, ']'); Halt(1); end;
  if gEcho <> 'pong6' then begin writeln('FAIL client got [', gEcho, ']'); Halt(1); end;
  if not gServerDone then begin writeln('FAIL server coroutine did not finish'); Halt(1); end;
  writeln('ASYNCNET6 OK');
end.
