program lib_http_pool;
{ End-to-end connection pool (feature-own-net-http-lib): the server coroutine
  does a SINGLE TcpAccept and serves TWO requests; the client makes two separate
  HttpGetPooledAsync calls to the same host:port. The pool transparently reuses
  the one connection — so the second GET succeeds against a server that only ever
  accepted once. }
uses scheduler, asyncnet, http;

const PORT = 28799;

var
  gBody1, gBody2: AnsiString;
  gServerDone: Boolean;

procedure ServerCo(arg: Pointer);
var lfd, cfd: Integer; buf: array[0..2047] of Byte; n: Int64; r1, r2: AnsiString;
begin
  r1 := 'HTTP/1.1 200 OK'#13#10'Content-Length: 5'#13#10'Connection: keep-alive'#13#10#13#10'first';
  r2 := 'HTTP/1.1 200 OK'#13#10'Content-Length: 6'#13#10'Connection: keep-alive'#13#10#13#10'second';
  lfd := TcpListen(PORT);
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
  a := HttpGetPooledAsync('http://127.0.0.1:28799/a');   { opens + pools }
  gBody1 := a.Body;
  b := HttpGetPooledAsync('http://127.0.0.1:28799/b');   { reuses the pooled conn }
  gBody2 := b.Body;
  HttpPoolClose;
end;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

begin
  gBody1 := ''; gBody2 := ''; gServerDone := False;
  Spawn(@ServerCo, nil);
  Spawn(@ClientCo, nil);
  RunUntilDone;

  SayBool('server-done', gServerDone);
  SayBool('body1', gBody1 = 'first');
  SayBool('body2-reused', gBody2 = 'second');   { proves the pool reused one conn }
end.
