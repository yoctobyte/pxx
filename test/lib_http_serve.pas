program lib_http_serve;
{ End-to-end server framework (feature-own-net-http-lib): a user-defined handler
  routes on req.Path / req.Query and returns a response built with
  HttpBuildResponse; HttpServeConn runs the per-connection read→dispatch→send loop
  over keep-alive. A client makes two requests on one connection; the second
  carries a query string the handler echoes back. All on one reactor thread. }
uses scheduler, asyncnet, http;


var
  gRoot, gEcho: AnsiString;
  gPort: Integer;          { the ephemeral port the server actually got }
  gServerDone: Boolean;

function MyHandler(const req: THttpRequest): AnsiString;
begin
  if req.Path = '/' then
    MyHandler := HttpBuildResponse(200, 'OK', 'Connection: keep-alive'#13#10, 'root')
  else if req.Path = '/echo' then
    MyHandler := HttpBuildResponse(200, 'OK', 'Connection: keep-alive'#13#10,
                                   'q=' + HttpQueryGet(req.Query, 'q'))
  else
    MyHandler := HttpBuildResponse(404, 'Not Found', 'Connection: keep-alive'#13#10, 'nope');
end;

procedure ServerCo(arg: Pointer);
var lfd, cfd: Integer;
begin
  { Port 0: the kernel picks a free port and TcpLocalPort reads back which one,
    published in gPort for the client coroutine. This used to hardcode 28855, and a
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
  cfd := TcpAccept(lfd);
  HttpServeConn(cfd, @MyHandler, 2, True);     { serve two keep-alive requests }
  TcpClose(cfd); TcpClose(lfd);
  gServerDone := True;
end;

procedure ClientCo(arg: Pointer);
var conn: THttpConnection; r: THttpResponse;
begin
  conn := HttpConnectAsync('127.0.0.1', gPort, False);
  r := HttpConnExecAsync(conn, 'GET', '/', '', '');           gRoot := r.Body;
  r := HttpConnExecAsync(conn, 'GET', '/echo?q=hi', '', '');  gEcho := r.Body;
  HttpConnClose(conn);
end;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

begin
  gRoot := ''; gEcho := ''; gServerDone := False; gPort := 0;
  Spawn(@ServerCo, nil);
  Spawn(@ClientCo, nil);
  RunUntilDone;

  { Named apart from server-done so a fixture failure reads as one -- the
    whole point of the ticket is that a lost port race used to be invisible. }
  SayBool('listen-port', gPort > 0);
  SayBool('server-done', gServerDone);
  SayBool('root', gRoot = 'root');
  SayBool('echo-query', gEcho = 'q=hi');
end.
