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

uses net, asyncnet, dns, dns_async, dns_config, dns_wire_core, sysutils;

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

{ Case-insensitive header lookup over a raw header block. Returns the value with
  surrounding whitespace trimmed, or '' if absent. }
function HttpHeaderValue(const headers, name: AnsiString): AnsiString;

{ Decode a chunked-transfer-encoded body to its plain bytes. }
function HttpDechunk(const body: AnsiString): AnsiString;

{ Resolve a (possibly relative) Location against a base URL: an absolute
  http(s):// location is returned as-is; an absolute-path '/x' keeps the base
  scheme+host+port; anything else resolves against the base path's directory. }
function HttpResolveUrl(const base, location: AnsiString): AnsiString;

{ Parse a raw response into resp (status line + headers + body). Applies
  Transfer-Encoding: chunked decoding, else trims the body to Content-Length. }
procedure HttpParseResponse(const raw: AnsiString; var resp: THttpResponse);

{ --- blocking transport --- }

function HttpGet(const url: AnsiString): THttpResponse;
function HttpPost(const url, contentType, body: AnsiString): THttpResponse;
function HttpHead(const url: AnsiString): THttpResponse;
function HttpPut(const url, contentType, body: AnsiString): THttpResponse;
function HttpDelete(const url: AnsiString): THttpResponse;

{ Generic request: any method + optional extra headers (CRLF-terminated lines) +
  body. A Content-Length is added automatically when body <> ''. }
function HttpExec(const method, url, extraHeaders, body: AnsiString): THttpResponse;

{ GET following up to maxRedirects 3xx Location hops (absolute Location URLs).
  Returns the final response (or the last 3xx if the limit is hit). }
function HttpGetFollow(const url: AnsiString; maxRedirects: Integer): THttpResponse;

{ --- async transport (call from inside a coroutine; drive with RunUntilDone) ---
  Non-blocking connect/send/recv over the scheduler's epoll reactor (via
  asyncnet): the coroutine yields on EAGAIN, so one thread serves many requests.
  Hostnames resolve via the async resolver (dns_async); reuses the same pure
  build/parse helpers. }
function HttpGetAsync(const url: AnsiString): THttpResponse;
function HttpPostAsync(const url, contentType, body: AnsiString): THttpResponse;
{ Async GET following up to maxRedirects 3xx Location hops (absolute URLs). }
function HttpGetFollowAsync(const url: AnsiString; maxRedirects: Integer): THttpResponse;

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

function HttpHeaderValue(const headers, name: AnsiString): AnsiString;
var
  lname, lhead, line: AnsiString;
  i, lineStart, colon: Integer;
begin
  Result := '';
  lname := LowerCase(name);
  lhead := LowerCase(headers);
  { Walk lines; match the name before its ':'. }
  lineStart := 1;
  for i := 1 to Length(lhead) + 1 do
    if (i > Length(lhead)) or (lhead[i] = #10) then
    begin
      line := Copy(lhead, lineStart, i - lineStart);
      { strip trailing CR }
      if (Length(line) > 0) and (line[Length(line)] = #13) then
        line := Copy(line, 1, Length(line) - 1);
      colon := Pos(':', line);
      if (colon > 0) and (Trim(Copy(line, 1, colon - 1)) = lname) then
      begin
        { return the value from the ORIGINAL (case-preserved) headers }
        Result := Trim(Copy(headers, lineStart + colon, i - (lineStart + colon)));
        if (Length(Result) > 0) and (Result[Length(Result)] = #13) then
          Result := Copy(Result, 1, Length(Result) - 1);
        Exit;
      end;
      lineStart := i + 1;
    end;
end;

function HttpDechunk(const body: AnsiString): AnsiString;
var
  pos, n, sz: Integer;
  hexline, outp: AnsiString;
  lineEnd: Integer;

  function HexVal(const s: AnsiString): Integer;
  var k, d: Integer; c: Char;
  begin
    Result := 0;
    for k := 1 to Length(s) do
    begin
      c := s[k];
      if (c >= '0') and (c <= '9') then d := Ord(c) - Ord('0')
      else if (c >= 'a') and (c <= 'f') then d := Ord(c) - Ord('a') + 10
      else if (c >= 'A') and (c <= 'F') then d := Ord(c) - Ord('A') + 10
      else Break;     { stop at ';' chunk-ext or whitespace }
      Result := Result * 16 + d;
    end;
  end;

begin
  outp := '';
  pos := 1;
  n := Length(body);
  while pos <= n do
  begin
    { chunk-size line up to CRLF }
    lineEnd := pos;
    while (lineEnd < n) and not ((body[lineEnd] = #13) and (body[lineEnd + 1] = #10)) do
      Inc(lineEnd);
    hexline := Copy(body, pos, lineEnd - pos);
    sz := HexVal(hexline);
    pos := lineEnd + 2;                 { past CRLF }
    if sz <= 0 then Break;              { last chunk }
    if pos + sz - 1 > n then sz := n - pos + 1;
    outp := outp + Copy(body, pos, sz);
    pos := pos + sz + 2;               { data + trailing CRLF }
  end;
  Result := outp;
end;

function HttpResolveUrl(const base, location: AnsiString): AnsiString;
var host, path, scheme, authority: AnsiString; port, i: Integer; isTls: Boolean;
begin
  if (Copy(location, 1, 7) = 'http://') or (Copy(location, 1, 8) = 'https://') then
  begin Result := location; Exit; end;
  if not HttpParseUrl(base, host, port, path, isTls) then
  begin Result := location; Exit; end;
  if isTls then scheme := 'https://' else scheme := 'http://';
  authority := host;
  if (isTls and (port <> 443)) or ((not isTls) and (port <> 80)) then
    authority := host + ':' + IntToStr(port);
  if (Length(location) > 0) and (location[1] = '/') then
    Result := scheme + authority + location
  else
  begin
    { relative to the base path's directory (everything up to the last '/') }
    i := Length(path);
    while (i > 0) and (path[i] <> '/') do Dec(i);
    Result := scheme + authority + Copy(path, 1, i) + location;
  end;
end;

procedure HttpParseResponse(const raw: AnsiString; var resp: THttpResponse);
var i, n, lineEnd, sp1, sp2, sep, cl: Integer; statusLine, code, te, clv: AnsiString;
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

  { Framing: chunked wins; else trim to Content-Length if given. }
  te := LowerCase(HttpHeaderValue(resp.Headers, 'Transfer-Encoding'));
  if Pos('chunked', te) > 0 then
    resp.Body := HttpDechunk(resp.Body)
  else
  begin
    clv := HttpHeaderValue(resp.Headers, 'Content-Length');
    if clv <> '' then
    begin
      cl := StrToIntDef(clv, -1);
      if (cl >= 0) and (cl < Length(resp.Body)) then
        resp.Body := Copy(resp.Body, 1, cl);
    end;
  end;

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

function HttpExec(const method, url, extraHeaders, body: AnsiString): THttpResponse;
begin
  Result := HttpRequest(method, url, extraHeaders, body);
end;

function HttpHead(const url: AnsiString): THttpResponse;
begin
  Result := HttpRequest('HEAD', url, '', '');
end;

function HttpPut(const url, contentType, body: AnsiString): THttpResponse;
var hdr: AnsiString;
begin
  hdr := '';
  if contentType <> '' then hdr := 'Content-Type: ' + contentType + CRLF;
  Result := HttpRequest('PUT', url, hdr, body);
end;

function HttpDelete(const url: AnsiString): THttpResponse;
begin
  Result := HttpRequest('DELETE', url, '', '');
end;

function HttpIsRedirect(status: Integer): Boolean;
begin
  Result := (status = 301) or (status = 302) or (status = 303)
         or (status = 307) or (status = 308);
end;

function HttpGetFollow(const url: AnsiString; maxRedirects: Integer): THttpResponse;
var cur, loc: AnsiString; hops: Integer;
begin
  cur := url;
  hops := 0;
  Result := HttpGet(cur);
  while Result.Ok and HttpIsRedirect(Result.Status) and (hops < maxRedirects) do
  begin
    loc := HttpHeaderValue(Result.Headers, 'Location');
    if loc = '' then Break;
    cur := HttpResolveUrl(cur, loc);
    Inc(hops);
    Result := HttpGet(cur);
  end;
end;

function HttpResolveAsync(const host: AnsiString; var ip: LongWord): Boolean;
var ips: TDnsIpv4Array; cnt: Integer;
begin
  cnt := 0;
  if DnsResolveHostAsync(host, ips, cnt) = 0 then
  begin
    if cnt > 0 then begin ip := ips[0]; Result := True; Exit; end;
  end;
  Result := False;
end;

function HttpRequestAsync(const method, url, extraHeaders, body: AnsiString): THttpResponse;
var
  host, path: AnsiString;
  port: Integer;
  isTls: Boolean;
  ip: LongWord;
  fd: Integer;
  req, raw: AnsiString;
  buf: array[0..4095] of Byte;
  n, i: Integer;
const
  BUFSZ = 4096;
begin
  Result.Ok := False; Result.Status := 0; Result.Reason := '';
  Result.Headers := ''; Result.Body := '';

  if not HttpParseUrl(url, host, port, path, isTls) then Exit;
  if isTls then Exit;                          { no TLS layer yet }
  if not HttpResolveAsync(host, ip) then Exit; { dotted-quad or hostname, async }

  fd := TcpConnectAddr(ip, port);              { yields until connected }
  if fd < 0 then Exit;

  req := HttpBuildRequest(method, host, path, extraHeaders, body);
  if TcpSend(fd, @req[1], Length(req)) < 0 then
  begin
    TcpClose(fd); Exit;
  end;

  raw := '';
  repeat
    n := TcpRecv(fd, @buf[0], BUFSZ);          { yields on EAGAIN }
    if n > 0 then
      for i := 0 to n - 1 do raw := raw + Chr(buf[i]);
  until n <= 0;
  TcpClose(fd);

  HttpParseResponse(raw, Result);
end;

function HttpGetAsync(const url: AnsiString): THttpResponse;
begin
  Result := HttpRequestAsync('GET', url, '', '');
end;

function HttpPostAsync(const url, contentType, body: AnsiString): THttpResponse;
var hdr: AnsiString;
begin
  hdr := '';
  if contentType <> '' then hdr := 'Content-Type: ' + contentType + CRLF;
  Result := HttpRequestAsync('POST', url, hdr, body);
end;

function HttpGetFollowAsync(const url: AnsiString; maxRedirects: Integer): THttpResponse;
var cur, loc: AnsiString; hops: Integer;
begin
  cur := url;
  hops := 0;
  Result := HttpGetAsync(cur);
  while Result.Ok and HttpIsRedirect(Result.Status) and (hops < maxRedirects) do
  begin
    loc := HttpHeaderValue(Result.Headers, 'Location');
    if loc = '' then Break;
    cur := HttpResolveUrl(cur, loc);
    Inc(hops);
    Result := HttpGetAsync(cur);
  end;
end;

end.
