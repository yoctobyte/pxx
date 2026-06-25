program lib_http_cookie;
{ End-to-end cookie round-trip (feature-own-net-http-lib): one keep-alive
  connection, two requests. The server sets a cookie on the first response; the
  client parses it into a jar (HttpCookieFromResponse) and sends it back as a
  Cookie header on the second request (HttpCookieHeader). The server confirms it
  saw the cookie and answers 'authed'. Composes the cookie jar + async keep-alive
  + structured response headers. }
uses scheduler, asyncnet, http;

const PORT = 28833;

var
  gSawCookie: Boolean;
  gJar: AnsiString;
  gBody2: AnsiString;
  gServerDone: Boolean;

function Contains(const hay, needle: AnsiString): Boolean;
begin
  Contains := Pos(needle, hay) > 0;
end;

procedure ServerCo(arg: Pointer);
var lfd, cfd: Integer; buf: array[0..2047] of Byte; n: Int64; req, r1, rAuth, rAnon: AnsiString; i: Integer;
begin
  r1    := 'HTTP/1.1 200 OK'#13#10'Set-Cookie: sid=xyz; Path=/'#13#10 +
           'Content-Length: 4'#13#10'Connection: keep-alive'#13#10#13#10'anon';
  rAuth := 'HTTP/1.1 200 OK'#13#10'Content-Length: 6'#13#10 +
           'Connection: keep-alive'#13#10#13#10'authed';
  rAnon := 'HTTP/1.1 200 OK'#13#10'Content-Length: 4'#13#10 +
           'Connection: keep-alive'#13#10#13#10'anon';

  lfd := TcpListen(PORT);
  cfd := TcpAccept(lfd);                       { ONE connection, two requests }

  n := TcpRecv(cfd, @buf[0], 2048);            { request 1: no cookie yet }
  TcpSend(cfd, @r1[1], Length(r1));

  n := TcpRecv(cfd, @buf[0], 2048);            { request 2: should carry Cookie }
  SetLength(req, n);
  for i := 1 to n do req[i] := AnsiChar(buf[i - 1]);
  gSawCookie := Contains(req, 'Cookie: sid=xyz');
  if gSawCookie then TcpSend(cfd, @rAuth[1], Length(rAuth))
  else               TcpSend(cfd, @rAnon[1], Length(rAnon));

  TcpClose(cfd); TcpClose(lfd);
  gServerDone := True;
end;

procedure ClientCo(arg: Pointer);
var conn: THttpConnection; a, b: THttpResponse;
begin
  conn := HttpConnectAsync('127.0.0.1', PORT, False);
  a := HttpConnExecAsync(conn, 'GET', '/', '', '');
  gJar := HttpCookieFromResponse('', a);              { learn the cookie }
  b := HttpConnExecAsync(conn, 'GET', '/', HttpCookieHeader(gJar), '');  { send it back }
  gBody2 := b.Body;
  HttpConnClose(conn);
end;

procedure SayBool(const tag: string; bv: Boolean);
begin
  if bv then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

begin
  gSawCookie := False; gJar := ''; gBody2 := ''; gServerDone := False;
  Spawn(@ServerCo, nil);
  Spawn(@ClientCo, nil);
  RunUntilDone;

  SayBool('server-done', gServerDone);
  SayBool('jar', gJar = 'sid=xyz');
  SayBool('server-saw-cookie', gSawCookie);
  SayBool('authed', gBody2 = 'authed');
end.
