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

function ReqPath(const req: AnsiString): AnsiString;
{ second token of the request line: 'GET /me HTTP/1.1' -> '/me' }
var i, s: Integer;
begin
  Result := '/';
  i := 1;
  while (i <= Length(req)) and (req[i] <> ' ') do Inc(i);
  Inc(i); s := i;
  while (i <= Length(req)) and (req[i] <> ' ') do Inc(i);
  if i > s then Result := Copy(req, s, i - s);
end;

procedure ServerCo(arg: Pointer);
var lfd, cfd, k: Integer; buf: array[0..2047] of Byte; n: Int64; req, path, resp: AnsiString; i: Integer;
begin
  lfd := TcpListen(PORT);
  cfd := TcpAccept(lfd);
  for k := 1 to 3 do                          { three keep-alive requests }
  begin
    n := TcpRecv(cfd, @buf[0], 2048);
    if n <= 0 then Break;
    SetLength(req, n);
    for i := 1 to n do req[i] := AnsiChar(buf[i - 1]);
    path := ReqPath(req);

    if path = '/' then
      resp := 'HTTP/1.1 200 OK'#13#10'Set-Cookie: sid=demo123; Path=/'#13#10 +
              'Content-Length: 21'#13#10'Connection: keep-alive'#13#10#13#10 +
              'Welcome to frank2 net'
    else if path = '/me' then
    begin
      if Pos('Cookie: sid=demo123', req) > 0 then
        resp := 'HTTP/1.1 200 OK'#13#10'Content-Length: 17'#13#10 +
                'Connection: keep-alive'#13#10#13#10'hello sid=demo123'
      else
        resp := 'HTTP/1.1 200 OK'#13#10'Content-Length: 5'#13#10 +
                'Connection: keep-alive'#13#10#13#10'anon!';
    end
    else
      resp := 'HTTP/1.1 200 OK'#13#10'Content-Encoding: gzip'#13#10 +
              'Content-Length: 31'#13#10'Connection: keep-alive'#13#10#13#10 + GzipHelloWorld;

    TcpSend(cfd, @resp[1], Length(resp));
  end;
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
