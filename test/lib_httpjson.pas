program lib_httpjson;
{ JSON-over-HTTP (feature-own-net-http-lib): a loopback server coroutine returns
  a JSON document; the client coroutine fetches+parses it with HttpGetJsonAsync
  and reads typed fields. Plus pure JsonParseSafe (good + malformed). One thread,
  reactor-driven. }
uses scheduler, asyncnet, http, json, httpjson;

const PORT = 28866;

var
  gName: AnsiString;
  gAge: Int64;
  gOk, gServerDone: Boolean;

procedure ServerCo(arg: Pointer);
var lfd, cfd: Integer; buf: array[0..2047] of Byte; n: Int64; resp: AnsiString;
begin
  resp := HttpBuildResponse(200, 'OK',
            'Content-Type: application/json'#13#10'Connection: close'#13#10,
            '{"name":"frank","age":2}');
  lfd := TcpListen(PORT);
  cfd := TcpAccept(lfd);
  n := TcpRecv(cfd, @buf[0], 2048);
  TcpSend(cfd, @resp[1], Length(resp));
  TcpClose(cfd); TcpClose(lfd);
  gServerDone := True;
end;

procedure ClientCo(arg: Pointer);
var v: TJSONValue;
begin
  v := HttpGetJsonAsync('http://127.0.0.1:28866/', gOk);
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
  gName := ''; gAge := -1; gOk := False; gServerDone := False;
  Spawn(@ServerCo, nil);
  Spawn(@ClientCo, nil);
  RunUntilDone;

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
