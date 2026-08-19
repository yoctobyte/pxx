program lib_http_pool;
{ End-to-end connection pool (feature-own-net-http-lib): the server coroutine
  does a SINGLE TcpAccept and serves TWO requests; the client makes two separate
  HttpGetPooledAsync calls to the same host:port. The pool transparently reuses
  the one connection — so the second GET succeeds against a server that only ever
  accepted once. }
uses scheduler, asyncnet, http, sysutils;


var
  gBody1, gBody2: AnsiString;
  gPort: Integer;          { the ephemeral port the server actually got }
  gServerDone: Boolean;

procedure ServerCo(arg: Pointer);
var lfd, cfd: Integer; buf: array[0..2047] of Byte; n: Int64; r1, r2: AnsiString;
begin
  r1 := 'HTTP/1.1 200 OK'#13#10'Content-Length: 5'#13#10'Connection: keep-alive'#13#10#13#10'first';
  r2 := 'HTTP/1.1 200 OK'#13#10'Content-Length: 6'#13#10'Connection: keep-alive'#13#10#13#10'second';
  { Port 0: the kernel picks a free port and TcpLocalPort reads back which one,
    published in gPort for the client coroutine. This used to hardcode 28799, and a
    hardcoded port is a shared global -- two copies of lib-test on one box fight
    over it, which is what Track T's watcher host does by design. With the
    TcpListen return ignored the loser did not fail either, it PARKED on the
    reactor forever
    (bug-b-lib-tls-hangs-forever-when-its-hardcoded-port-is-unavailable). }
  lfd := TcpListen(0);
  if lfd < 0 then begin gPort := -1; writeln('listen-failed'); Exit; end;
  gPort := TcpLocalPort(lfd);
  if gPort <= 0 then
  begin
    gPort := -1;
    writeln('listen-failed');
    TcpClose(lfd);
    Exit;
  end;
  cfd := TcpAccept(lfd);                  { ONE accept for both pooled requests }
  n := TcpRecv(cfd, @buf[0], 2048);  TcpSend(cfd, @r1[1], Length(r1));
  n := TcpRecv(cfd, @buf[0], 2048);  TcpSend(cfd, @r2[1], Length(r2));
  TcpClose(cfd);
  TcpClose(lfd);
  gServerDone := True;
end;

procedure ClientCo(arg: Pointer);
var a, b: THttpResponse;
begin
  a := HttpGetPooledAsync('http://127.0.0.1:' + IntToStr(gPort) + '/a');   { opens + pools }
  gBody1 := a.Body;
  b := HttpGetPooledAsync('http://127.0.0.1:' + IntToStr(gPort) + '/b');   { reuses the pooled conn }
  gBody2 := b.Body;
  HttpPoolClose;
end;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

begin
  gBody1 := ''; gBody2 := ''; gServerDone := False; gPort := 0;
  Spawn(@ServerCo, nil);
  Spawn(@ClientCo, nil);
  RunUntilDone;

  { Named apart from server-done so a fixture failure reads as one -- the
    whole point of the ticket is that a lost port race used to be invisible. }
  SayBool('listen-port', gPort > 0);
  SayBool('server-done', gServerDone);
  SayBool('body1', gBody1 = 'first');
  SayBool('body2-reused', gBody2 = 'second');   { proves the pool reused one conn }
end.
