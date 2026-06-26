program lib_http_serve;
{ End-to-end server framework (feature-own-net-http-lib): a user-defined handler
  routes on req.Path / req.Query and returns a response built with
  HttpBuildResponse; HttpServeConn runs the per-connection read→dispatch→send loop
  over keep-alive. A client makes two requests on one connection; the second
  carries a query string the handler echoes back. All on one reactor thread. }
uses scheduler, asyncnet, http;

const PORT = 28855;

var
  gRoot, gEcho: AnsiString;
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
  lfd := TcpListen(PORT);
  cfd := TcpAccept(lfd);
  HttpServeConn(cfd, @MyHandler, 2, True);     { serve two keep-alive requests }
  TcpClose(cfd); TcpClose(lfd);
  gServerDone := True;
end;

procedure ClientCo(arg: Pointer);
var conn: THttpConnection; r: THttpResponse;
begin
  conn := HttpConnectAsync('127.0.0.1', PORT, False);
  r := HttpConnExecAsync(conn, 'GET', '/', '', '');           gRoot := r.Body;
  r := HttpConnExecAsync(conn, 'GET', '/echo?q=hi', '', '');  gEcho := r.Body;
  HttpConnClose(conn);
end;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

begin
  gRoot := ''; gEcho := ''; gServerDone := False;
  Spawn(@ServerCo, nil);
  Spawn(@ClientCo, nil);
  RunUntilDone;

  SayBool('server-done', gServerDone);
  SayBool('root', gRoot = 'root');
  SayBool('echo-query', gEcho = 'q=hi');
end.
