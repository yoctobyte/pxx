program lib_http_async;
{ End-to-end async HTTP over the coroutine reactor (feature-own-net-http-lib):
  a server coroutine and a client coroutine run on ONE thread, both yielding via
  the epoll reactor. Proves the async socket path AND HttpGetAsync against a real
  loopback server — the proof-of-concept a blocking client cannot do single-thread. }
uses scheduler, asyncnet, http, sysutils;

{ No hardcoded port. The server listens on 0 and publishes what the kernel gave
  it in gPort, which the client reads before it builds its URL. A fixed port is a
  shared global, and this test used to hold 28755 — the SAME number lib_tls held,
  in the same lib-test recipe — with the TcpListen return ignored, so a lost race
  parked TcpAccept on the reactor forever
  (bug-b-lib-tls-hangs-forever-when-its-hardcoded-port-is-unavailable). }

var
  gPort:   Integer;
  gStatus: Integer;
  gBody:   AnsiString;
  gReason: AnsiString;
  gServerDone: Boolean;

procedure ServerCo(arg: Pointer);
var lfd, cfd: Integer; buf: array[0..2047] of Byte; n: Int64; resp: AnsiString;
begin
  lfd := TcpListen(0);                    { 0 = let the kernel pick a free port }
  if lfd < 0 then begin gPort := -1; gServerDone := False; Exit; end;
  gPort := TcpLocalPort(lfd);             { ...and tell the client which one }
  if gPort <= 0 then begin TcpClose(lfd); gPort := -1; Exit; end;
  cfd := TcpAccept(lfd);                  { yields until the client connects }
  n := TcpRecv(cfd, @buf[0], 2048);       { read the request (one segment) }
  resp := 'HTTP/1.1 200 OK'#13#10 +
          'Content-Length: 5'#13#10 +
          'Connection: close'#13#10#13#10 +
          'hello';
  TcpSend(cfd, @resp[1], Length(resp));
  TcpClose(cfd);                          { close -> client sees EOF }
  TcpClose(lfd);
  gServerDone := True;
end;

procedure ClientCo(arg: Pointer);
var r: THttpResponse;
begin
  { The server coroutine is spawned first and runs to its first yield (inside
    TcpAccept) before this one starts, so gPort is already set. A failed listen
    leaves it -1, and this exits rather than dialling port -1. }
  if gPort <= 0 then Exit;
  r := HttpGetAsync('http://127.0.0.1:' + IntToStr(gPort) + '/');
  gStatus := r.Status;
  gReason := r.Reason;
  gBody := r.Body;
end;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

begin
  gStatus := -1; gBody := ''; gReason := ''; gServerDone := False; gPort := 0;
  Spawn(@ServerCo, nil);                  { listen first }
  Spawn(@ClientCo, nil);
  RunUntilDone;                           { reactor drives both to completion }

  SayBool('listen-port', gPort > 0);
  SayBool('server-done', gServerDone);
  SayBool('status', gStatus = 200);
  SayBool('reason', gReason = 'OK');
  SayBool('body', gBody = 'hello');
end.
