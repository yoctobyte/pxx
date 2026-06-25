program httpdemo;
{ frank2 native net-lib showcase — no external network needed.

  A loopback HTTP/1.1 server coroutine and a client coroutine run on ONE thread,
  both driven by the epoll reactor (scheduler). Over a single keep-alive
  connection the client makes three requests and the demo prints a transcript:

    1. GET /          → a welcome page; the server sets a cookie
    2. GET /me        → the client sends the cookie back; the server greets it
    3. GET /data.gz   → a gzip-compressed body the client decodes transparently

  Run:  pxx -Fulib/rtl/platform/posix examples/net/httpdemo.pas /tmp/httpdemo && /tmp/httpdemo }
uses scheduler, asyncnet, http;

const PORT = 28844;

function GzipHelloWorld: AnsiString;
{ gzip member for 'hello world' (Python gzip, mtime=0). }
const b: array[0..30] of Integer = (
  31, 139, 8, 0, 0, 0, 0, 0, 2, 255, 203, 72, 205, 201, 201, 87, 40, 207,
  47, 202, 73, 1, 0, 133, 17, 74, 13, 11, 0, 0, 0);
var i: Integer;
begin
  SetLength(Result, 31);
  for i := 0 to 30 do Result[i + 1] := AnsiChar(b[i]);
end;

const KEEPALIVE = 'Connection: keep-alive'#13#10;

{ A routing handler — the whole "site". HttpServeConn calls it per request and
  computes Content-Length via HttpBuildResponse, so no hand-counting. }
function DemoHandler(const req: THttpRequest): AnsiString;
begin
  if req.Path = '/' then
    DemoHandler := HttpBuildResponse(200, 'OK',
                     'Set-Cookie: sid=demo123; Path=/'#13#10 + KEEPALIVE,
                     'Welcome to frank2 net')
  else if req.Path = '/me' then
  begin
    if Pos('sid=demo123', HttpRequestHeader(req, 'Cookie')) > 0 then
      DemoHandler := HttpBuildResponse(200, 'OK', KEEPALIVE, 'hello sid=demo123')
    else
      DemoHandler := HttpBuildResponse(200, 'OK', KEEPALIVE, 'anon!');
  end
  else
    DemoHandler := HttpBuildResponse(200, 'OK',
                     'Content-Encoding: gzip'#13#10 + KEEPALIVE, GzipHelloWorld);
end;

procedure ServerCo(arg: Pointer);
var lfd, cfd: Integer;
begin
  lfd := TcpListen(PORT);
  cfd := TcpAccept(lfd);
  HttpServeConn(cfd, @DemoHandler, 3, True);   { the per-connection serve loop }
  TcpClose(cfd); TcpClose(lfd);
end;

procedure ClientCo(arg: Pointer);
var conn: THttpConnection; r: THttpResponse; jar: AnsiString;
begin
  conn := HttpConnectAsync('127.0.0.1', PORT, False);

  r := HttpConnExecAsync(conn, 'GET', '/', '', '');
  writeln('GET /        -> ', r.Status, ' ', r.Reason);
  writeln('  body:   ', r.Body);
  jar := HttpCookieFromResponse('', r);
  writeln('  cookie: ', jar);

  r := HttpConnExecAsync(conn, 'GET', '/me', HttpCookieHeader(jar), '');
  writeln('GET /me      -> ', r.Status, ' ', r.Reason, '  (cookie sent back)');
  writeln('  body:   ', r.Body);

  r := HttpConnExecAsync(conn, 'GET', '/data.gz', '', '');
  writeln('GET /data.gz -> ', r.Status, ' ', r.Reason, '  (gzip, decoded transparently)');
  writeln('  body:   ', r.Body);

  HttpConnClose(conn);
  writeln('done');
end;

begin
  Spawn(@ServerCo, nil);
  Spawn(@ClientCo, nil);
  RunUntilDone;
end.
