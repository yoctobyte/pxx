program lib_http_keepalive;
{ End-to-end keep-alive (feature-own-net-http-lib): the server coroutine does a
  SINGLE TcpAccept and serves TWO sequential requests on that one connection;
  the client reuses one THttpConnection for both GETs (length-aware reads, so the
  socket survives between responses). Proves connection reuse + Content-Length
  framing without read-to-EOF. }
uses scheduler, asyncnet, http;

const PORT = 28788;

var
  gBody1, gBody2: AnsiString;
  gAliveMid: Boolean;
  gServerDone: Boolean;

procedure ServerCo(arg: Pointer);
var lfd, cfd: Integer; buf: array[0..2047] of Byte; n: Int64; resp1, resp2: AnsiString;
begin
  resp1 := 'HTTP/1.1 200 OK'#13#10'Content-Length: 5'#13#10'Connection: keep-alive'#13#10#13#10'first';
  resp2 := 'HTTP/1.1 200 OK'#13#10'Content-Length: 6'#13#10'Connection: keep-alive'#13#10#13#10'second';
  lfd := TcpListen(PORT);
  cfd := TcpAccept(lfd);                 { ONE connection for both requests }

  n := TcpRecv(cfd, @buf[0], 2048);      { request 1 }
  TcpSend(cfd, @resp1[1], Length(resp1));

  n := TcpRecv(cfd, @buf[0], 2048);      { request 2 — same socket }
  TcpSend(cfd, @resp2[1], Length(resp2));

  TcpClose(cfd);
  TcpClose(lfd);
  gServerDone := True;
end;

procedure ClientCo(arg: Pointer);
var conn: THttpConnection; r1, r2: THttpResponse;
begin
  conn := HttpConnectAsync('127.0.0.1', PORT, False);   { plaintext }
  r1 := HttpConnGetAsync(conn, '/a');
  gBody1 := r1.Body;
  gAliveMid := conn.Alive;               { still alive between requests }
  r2 := HttpConnGetAsync(conn, '/b');    { reuses the same connection }
  gBody2 := r2.Body;
  HttpConnClose(conn);
end;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

begin
  gBody1 := ''; gBody2 := ''; gAliveMid := False; gServerDone := False;
  Spawn(@ServerCo, nil);
  Spawn(@ClientCo, nil);
  RunUntilDone;

  SayBool('server-done', gServerDone);
  SayBool('body1', gBody1 = 'first');
  SayBool('alive-mid', gAliveMid);
  SayBool('body2', gBody2 = 'second');
end.
