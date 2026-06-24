program lib_http_async;
{ End-to-end async HTTP over the coroutine reactor (feature-own-net-http-lib):
  a server coroutine and a client coroutine run on ONE thread, both yielding via
  the epoll reactor. Proves the async socket path AND HttpGetAsync against a real
  loopback server — the proof-of-concept a blocking client cannot do single-thread. }
uses scheduler, asyncnet, http;

const PORT = 28755;

var
  gStatus: Integer;
  gBody:   AnsiString;
  gReason: AnsiString;
  gServerDone: Boolean;

procedure ServerCo(arg: Pointer);
var lfd, cfd: Integer; buf: array[0..2047] of Byte; n: Int64; resp: AnsiString;
begin
  lfd := TcpListen(PORT);
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
  r := HttpGetAsync('http://127.0.0.1:28755/');
  gStatus := r.Status;
  gReason := r.Reason;
  gBody := r.Body;
end;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

begin
  gStatus := -1; gBody := ''; gReason := ''; gServerDone := False;
  Spawn(@ServerCo, nil);                  { listen first }
  Spawn(@ClientCo, nil);
  RunUntilDone;                           { reactor drives both to completion }

  SayBool('server-done', gServerDone);
  SayBool('status', gStatus = 200);
  SayBool('reason', gReason = 'OK');
  SayBool('body', gBody = 'hello');
end.
