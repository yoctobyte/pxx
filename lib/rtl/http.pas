unit http;
{ Minimal native HTTP/1.1 client (our own net stack — NOT a Synapse shim).
  Built on lib/rtl/net (blocking TCP) + lib/rtl/dns (resolution). The request
  build / response parse / URL parse are pure string helpers, kept public and
  I/O-free so they are deterministically testable and so an async transport
  (over scheduler's epoll reactor: SetNonBlocking + WaitReadable) can reuse them
  without duplicating the protocol logic.

  Scope now: plain HTTP (no TLS — https needs a TLS layer, a separate unit),
  GET/POST, `Connection: close` response framing (read to EOF). Chunked /
  keep-alive framing is a later slice. }

interface

uses net, dns, dns_config, dns_wire_core, sysutils;

type
  THttpResponse = record
    Ok:      Boolean;      { transport + parse succeeded }
    Status:  Integer;      { e.g. 200; 0 if unparsed }
    Reason:  AnsiString;   { e.g. 'OK' }
    Headers: AnsiString;   { raw header block (no status line, no final CRLF) }
    Body:    AnsiString;
  end;

{ --- pure helpers (no I/O) --- }

{ Split `http://host[:port][/path]`. Returns False if not http:// or no host.
  Defaults: port 80, path '/'. (https:// is recognised but reported via isTls so
  the caller can refuse until a TLS layer exists.) }
function HttpParseUrl(const url: AnsiString;
  var host: AnsiString; var port: Integer; var path: AnsiString;
  var isTls: Boolean): Boolean;

{ Build a request. extraHeaders, if non-empty, must be CRLF-terminated lines.
  A Content-Length is added automatically when body <> ''. }
function HttpBuildRequest(const method, host, path, extraHeaders, body: AnsiString): AnsiString;

{ Parse a raw response into resp (status line + headers + body). }
procedure HttpParseResponse(const raw: AnsiString; var resp: THttpResponse);

{ --- blocking transport --- }

function HttpGet(const url: AnsiString): THttpResponse;
function HttpPost(const url, contentType, body: AnsiString): THttpResponse;

implementation

const
  CRLF = #13#10;

function HttpParseUrl(const url: AnsiString;
  var host: AnsiString; var port: Integer; var path: AnsiString;
  var isTls: Boolean): Boolean;
var i, n, colon: Integer; rest, hostport: AnsiString;
begin
  Result := False;
  host := ''; path := '/'; isTls := False; port := 80;
  n := Length(url);
  if Copy(url, 1, 7) = 'http://' then
    rest := Copy(url, 8, n)
  else if Copy(url, 1, 8) = 'https://' then
  begin
    isTls := True; port := 443; rest := Copy(url, 9, n);
  end
  else
    Exit;

  { host[:port] is up to the first '/'. }
  i := 1;
  while (i <= Length(rest)) and (rest[i] <> '/') do Inc(i);
  hostport := Copy(rest, 1, i - 1);
  if i <= Length(rest) then path := Copy(rest, i, Length(rest));
  if path = '' then path := '/';

  { optional :port }
  colon := 0;
  for i := 1 to Length(hostport) do
    if hostport[i] = ':' then colon := i;
  if colon > 0 then
  begin
    host := Copy(hostport, 1, colon - 1);
    port := StrToIntDef(Copy(hostport, colon + 1, Length(hostport)), port);
  end
  else
    host := hostport;

  Result := host <> '';
end;

function HttpBuildRequest(const method, host, path, extraHeaders, body: AnsiString): AnsiString;
var r: AnsiString;
begin
  r := method + ' ' + path + ' HTTP/1.1' + CRLF;
  r := r + 'Host: ' + host + CRLF;
  r := r + 'Connection: close' + CRLF;
  if extraHeaders <> '' then r := r + extraHeaders;
  if body <> '' then
    r := r + 'Content-Length: ' + IntToStr(Length(body)) + CRLF;
  r := r + CRLF;          { end of headers }
  if body <> '' then r := r + body;
  Result := r;
end;

procedure HttpParseResponse(const raw: AnsiString; var resp: THttpResponse);
var i, n, lineEnd, sp1, sp2, sep: Integer; statusLine, code: AnsiString;
begin
  resp.Ok := False; resp.Status := 0; resp.Reason := '';
  resp.Headers := ''; resp.Body := '';
  n := Length(raw);
  if n = 0 then Exit;

  { status line up to first CRLF }
  lineEnd := 1;
  while (lineEnd < n) and not ((raw[lineEnd] = #13) and (raw[lineEnd + 1] = #10)) do
    Inc(lineEnd);
  statusLine := Copy(raw, 1, lineEnd - 1);

  { 'HTTP/1.1 200 OK' -> code between the first two spaces }
  sp1 := 0; sp2 := 0;
  for i := 1 to Length(statusLine) do
    if statusLine[i] = ' ' then
    begin
      if sp1 = 0 then sp1 := i
      else if sp2 = 0 then begin sp2 := i; end;
    end;
  if sp1 > 0 then
  begin
    if sp2 > 0 then
    begin
      code := Copy(statusLine, sp1 + 1, sp2 - sp1 - 1);
      resp.Reason := Copy(statusLine, sp2 + 1, Length(statusLine));
    end
    else
      code := Copy(statusLine, sp1 + 1, Length(statusLine));
    resp.Status := StrToIntDef(code, 0);
  end;

  { headers/body split at CRLFCRLF }
  sep := 0;
  for i := 1 to n - 3 do
    if (raw[i] = #13) and (raw[i + 1] = #10) and
       (raw[i + 2] = #13) and (raw[i + 3] = #10) then
    begin sep := i; break; end;
  if sep > 0 then
  begin
    { headers start after the status-line CRLF }
    if lineEnd + 2 <= sep - 1 then
      resp.Headers := Copy(raw, lineEnd + 2, sep - (lineEnd + 2));
    resp.Body := Copy(raw, sep + 4, n);
  end
  else
    resp.Headers := Copy(raw, lineEnd + 2, n);

  resp.Ok := resp.Status > 0;
end;

function HttpResolve(const host: AnsiString; var ip: LongWord): Boolean;
var ips: TDnsIpv4Array; cnt, rc: Integer;
begin
  { dotted-quad first (no DNS round-trip), else resolve. }
  if DnsParseIpv4(host, 1, Length(host), ip) then
  begin
    Result := True;
    Exit;
  end;
  cnt := 0;
  rc := DnsResolveHost(host, ips, cnt);
  if (rc = 0) and (cnt > 0) then
  begin
    ip := ips[0];
    Result := True;
  end
  else
    Result := False;
end;

function HttpRequest(const method, url, extraHeaders, body: AnsiString): THttpResponse;
var
  host, path: AnsiString;
  port: Integer;
  isTls: Boolean;
  ip: LongWord;
  sock: TNetSocket;
  req, raw: AnsiString;
  buf: array[0..4095] of Byte;
  n, i: Integer;
const
  BUFSZ = 4096;
begin
  Result.Ok := False; Result.Status := 0; Result.Reason := '';
  Result.Headers := ''; Result.Body := '';

  if not HttpParseUrl(url, host, port, path, isTls) then Exit;
  if isTls then Exit;                 { no TLS layer yet }
  if not HttpResolve(host, ip) then Exit;

  sock := NetTcpConnect(NetAddress(ip, port));
  if sock < 0 then Exit;

  req := HttpBuildRequest(method, host, path, extraHeaders, body);
  if NetSend(sock, @req[1], Length(req)) < 0 then
  begin
    NetClose(sock); Exit;
  end;

  raw := '';
  repeat
    n := NetRecv(sock, @buf[0], BUFSZ);
    if n > 0 then
      for i := 0 to n - 1 do raw := raw + Chr(buf[i]);
  until n <= 0;
  NetClose(sock);

  HttpParseResponse(raw, Result);
end;

function HttpGet(const url: AnsiString): THttpResponse;
begin
  Result := HttpRequest('GET', url, '', '');
end;

function HttpPost(const url, contentType, body: AnsiString): THttpResponse;
var hdr: AnsiString;
begin
  hdr := '';
  if contentType <> '' then hdr := 'Content-Type: ' + contentType + CRLF;
  Result := HttpRequest('POST', url, hdr, body);
end;

end.
