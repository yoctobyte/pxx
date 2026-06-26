program lib_http_gzip;
{ End-to-end gzip content-decoding (feature-own-net-http-lib): a server coroutine
  serves a gzip-compressed body with Content-Encoding: gzip; the client's
  HttpGetAsync decodes it transparently (HttpParseResponse → HttpDecodeContent).
  Also checks the client advertised Accept-Encoding in its request. }
uses scheduler, asyncnet, http;

const PORT = 28822;

var
  gStatus: Integer;
  gBody:   AnsiString;
  gAdvertised: Boolean;
  gServerDone: Boolean;

function GzipHelloWorld: AnsiString;
{ gzip member for 'hello world' (Python gzip, mtime=0) as a binary string. }
const b: array[0..30] of Integer = (
  31, 139, 8, 0, 0, 0, 0, 0, 2, 255, 203, 72, 205, 201, 201, 87, 40, 207,
  47, 202, 73, 1, 0, 133, 17, 74, 13, 11, 0, 0, 0);
var i: Integer;
begin
  SetLength(Result, 31);
  for i := 0 to 30 do Result[i + 1] := AnsiChar(b[i]);
end;

function ToLowerStr(const s: AnsiString): AnsiString;
var i: Integer; c: AnsiChar;
begin
  SetLength(Result, Length(s));
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c >= 'A') and (c <= 'Z') then c := AnsiChar(Ord(c) + 32);
    Result[i] := c;
  end;
end;

procedure ServerCo(arg: Pointer);
var lfd, cfd: Integer; buf: array[0..2047] of Byte; n: Int64; req, resp: AnsiString; i: Integer;
begin
  lfd := TcpListen(PORT);
  cfd := TcpAccept(lfd);
  n := TcpRecv(cfd, @buf[0], 2048);
  SetLength(req, n);
  for i := 1 to n do req[i] := AnsiChar(buf[i - 1]);
  gAdvertised := Pos('accept-encoding:', ToLowerStr(req)) > 0;
  resp := 'HTTP/1.1 200 OK'#13#10 +
          'Content-Encoding: gzip'#13#10 +
          'Content-Length: 31'#13#10 +
          'Connection: close'#13#10#13#10 + GzipHelloWorld;
  TcpSend(cfd, @resp[1], Length(resp));
  TcpClose(cfd);
  TcpClose(lfd);
  gServerDone := True;
end;

procedure ClientCo(arg: Pointer);
var r: THttpResponse;
begin
  r := HttpGetAsync('http://127.0.0.1:28822/');
  gStatus := r.Status;
  gBody := r.Body;
end;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

begin
  gStatus := -1; gBody := ''; gAdvertised := False; gServerDone := False;
  Spawn(@ServerCo, nil);
  Spawn(@ClientCo, nil);
  RunUntilDone;

  SayBool('server-done', gServerDone);
  SayBool('status', gStatus = 200);
  SayBool('advertised', gAdvertised);          { client sent Accept-Encoding }
  SayBool('body-decoded', gBody = 'hello world');  { gzip body inflated for free }
end.
