program lib_httpjson;
{ JSON-over-HTTP (feature-own-net-http-lib): a loopback server coroutine returns
  a JSON document; the client coroutine fetches+parses it with HttpGetJsonAsync
  and reads typed fields. Plus pure JsonParseSafe (good + malformed). One thread,
  reactor-driven. }
uses scheduler, asyncnet, http, json, httpjson, sysutils;


var
  gName: AnsiString;
  gAge: Int64;
  gPort: Integer;          { the ephemeral port the server actually got }
  gOk, gServerDone: Boolean;

procedure ServerCo(arg: Pointer);
var lfd, cfd: Integer; buf: array[0..2047] of Byte; n: Int64; resp: AnsiString;
begin
  resp := HttpBuildResponse(200, 'OK',
            'Content-Type: application/json'#13#10'Connection: close'#13#10,
            '{"name":"frank","age":2}');
  { Port 0: the kernel picks a free port and TcpLocalPort reads back which one,
    published in gPort for the client coroutine. This used to hardcode 28866, and a
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
  n := TcpRecv(cfd, @buf[0], 2048);
  TcpSend(cfd, @resp[1], Length(resp));
  TcpClose(cfd); TcpClose(lfd);
  gServerDone := True;
end;

procedure ClientCo(arg: Pointer);
var v: TJSONValue;
begin
  v := HttpGetJsonAsync('http://127.0.0.1:' + IntToStr(gPort) + '/', gOk);
  if gOk and (v <> nil) then
  begin
    gName := v.GetValue('name').AsString;
    gAge  := v.GetValue('age').AsInteger;
    v.FreeTree;
  end;
end;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

var v: TJSONValue; okGood, okBad: Boolean;
begin
  gName := ''; gAge := -1; gOk := False; gServerDone := False; gPort := 0;
  Spawn(@ServerCo, nil);
  Spawn(@ClientCo, nil);
  RunUntilDone;

  { Named apart from server-done so a fixture failure reads as one -- the
    whole point of the ticket is that a lost port race used to be invisible. }
  SayBool('listen-port', gPort > 0);
  SayBool('server-done', gServerDone);
  SayBool('fetch-ok', gOk);
  SayBool('name', gName = 'frank');
  SayBool('age', gAge = 2);

  { pure parse helper }
  v := JsonParseSafe('{"x":1}', okGood);
  SayBool('parse-good', okGood and (v <> nil));
  if v <> nil then v.FreeTree;
  v := JsonParseSafe('{bad json', okBad);
  SayBool('parse-bad', not okBad);
end.
