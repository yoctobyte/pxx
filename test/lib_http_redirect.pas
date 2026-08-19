program lib_http_redirect;
{ End-to-end redirect following over the reactor (feature-own-net-http-lib):
  a server coroutine answers the first request with 302 + Location and the second
  with 200; the client coroutine HttpGetFollowAsync follows the hop. Proves the
  redirect loop AND multi-connection async on one thread. }
uses scheduler, asyncnet, http, sysutils;


var
  gStatus: Integer;
  gBody:   AnsiString;
  gPort: Integer;          { the ephemeral port the server actually got }
  gServerDone: Boolean;

procedure Serve(cfd: Integer; const resp: AnsiString);
var buf: array[0..2047] of Byte; n: Int64;
begin
  n := TcpRecv(cfd, @buf[0], 2048);     { consume the request }
  TcpSend(cfd, @resp[1], Length(resp));
  TcpClose(cfd);
end;

procedure ServerCo(arg: Pointer);
var lfd, c1, c2: Integer;
begin
  { Port 0: the kernel picks a free port and TcpLocalPort reads back which one,
    published in gPort for the client coroutine. This used to hardcode 28777, and a
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

  c1 := TcpAccept(lfd);                  { first request -> 302 }
  Serve(c1,
    'HTTP/1.1 302 Found'#13#10 +
    'Location: http://127.0.0.1:' + IntToStr(gPort) + '/final'#13#10 +
    'Content-Length: 0'#13#10 +
    'Connection: close'#13#10#13#10);

  c2 := TcpAccept(lfd);                  { followed request -> 200 }
  Serve(c2,
    'HTTP/1.1 200 OK'#13#10 +
    'Content-Length: 10'#13#10 +
    'Connection: close'#13#10#13#10 +
    'final-page');

  TcpClose(lfd);
  gServerDone := True;
end;

procedure ClientCo(arg: Pointer);
var r: THttpResponse;
begin
  r := HttpGetFollowAsync('http://127.0.0.1:' + IntToStr(gPort) + '/', 3);
  gStatus := r.Status;
  gBody := r.Body;
end;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

begin
  gStatus := -1; gBody := ''; gServerDone := False; gPort := 0;
  Spawn(@ServerCo, nil);
  Spawn(@ClientCo, nil);
  RunUntilDone;

  { Named apart from server-done so a fixture failure reads as one -- the
    whole point of the ticket is that a lost port race used to be invisible. }
  SayBool('listen-port', gPort > 0);
  SayBool('server-done', gServerDone);
  SayBool('status', gStatus = 200);
  SayBool('body', gBody = 'final-page');
end.
