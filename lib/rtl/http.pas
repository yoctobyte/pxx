unit http;
{ Minimal native HTTP/1.1 client (our own net stack — NOT a Synapse shim).
  Built on lib/rtl/net (blocking TCP) + lib/rtl/dns (resolution). The request
  build / response parse / URL parse are pure string helpers, kept public and
  I/O-free so they are deterministically testable and so an async transport
  (over scheduler's epoll reactor: SetNonBlocking + WaitReadable) can reuse them
  without duplicating the protocol logic.

  Capabilities: HTTP + https through the pluggable TLS seam (tls.pas) — bytes
  route via the active backend when the URL is https and a backend is registered,
  else an https request fails cleanly (no backend ships in-tree yet — see
  feature-tls-provider-abstraction);
  GET/POST/HEAD/PUT/DELETE + generic HttpExec with custom headers; blocking and
  async (reactor) transports; hostname resolution (blocking dns / async
  dns_async); response framing (Transfer-Encoding: chunked decode, else
  Content-Length); redirect following with relative-Location resolution.
  Next: keep-alive / connection reuse (today one request per Connection: close,
  which the parser frames correctly); a structured header map. }

interface

uses net, asyncnet, dns, dns_async, dns_config, dns_wire_core, sysutils,
     tls, scheduler, platform;

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

type
  THttpHeaderPair = record Name, Value: AnsiString; end;
  THttpHeaders = record
    List:  array of THttpHeaderPair;
    Count: Integer;
  end;

{ Parse a raw header block into name/value pairs (trimmed). Multi-value headers
  appear as repeated entries in order. }
function HttpParseHeaders(const block: AnsiString): THttpHeaders;
{ Case-insensitive first-match value, or '' if absent. }
function HttpHeadersGet(const h: THttpHeaders; const name: AnsiString): AnsiString;
function HttpHeadersHas(const h: THttpHeaders; const name: AnsiString): Boolean;
{ i in 0..h.Count-1. }
function HttpHeaderName(const h: THttpHeaders; i: Integer): AnsiString;
function HttpHeaderVal(const h: THttpHeaders; i: Integer): AnsiString;

{ Structured headers off a response: parse the raw `.Headers` block on demand
  (the response keeps headers raw to stay record-field-bug-free; these are the
  convenience seam over HttpParseHeaders / HttpHeaderValue). }
function HttpResponseHeaders(const resp: THttpResponse): THttpHeaders;
function HttpResponseHeader(const resp: THttpResponse; const name: AnsiString): AnsiString;

{ Decode a chunked-transfer-encoded body to its plain bytes. }
function HttpDechunk(const body: AnsiString): AnsiString;

{ Resolve a (possibly relative) Location against a base URL: an absolute
  http(s):// location is returned as-is; an absolute-path '/x' keeps the base
  scheme+host+port; anything else resolves against the base path's directory. }
function HttpResolveUrl(const base, location: AnsiString): AnsiString;

{ Percent-encode for URLs (RFC 3986 unreserved A-Za-z0-9-_.~ kept; everything
  else -> %XX, space -> %20). Decode reverses it and also maps '+' -> space. }
function HttpUrlEncode(const s: AnsiString): AnsiString;
function HttpUrlDecode(const s: AnsiString): AnsiString;

{ Append `name=value` (both percent-encoded) to a query/form string q, inserting
  '&' when q is non-empty. Serves both `?query` strings and
  application/x-www-form-urlencoded bodies. }
function HttpQueryAdd(const q, name, value: AnsiString): AnsiString;

{ Parse a raw response into resp (status line + headers + body). Applies
  Transfer-Encoding: chunked decoding, else trims the body to Content-Length. }
procedure HttpParseResponse(const raw: AnsiString; var resp: THttpResponse);

{ --- blocking transport --- }

function HttpGet(const url: AnsiString): THttpResponse;
function HttpPost(const url, contentType, body: AnsiString): THttpResponse;
function HttpHead(const url: AnsiString): THttpResponse;
function HttpPut(const url, contentType, body: AnsiString): THttpResponse;
function HttpDelete(const url: AnsiString): THttpResponse;
{ POST an application/x-www-form-urlencoded body (build it with HttpQueryAdd). }
function HttpPostForm(const url, formBody: AnsiString): THttpResponse;

{ Generic request: any method + optional extra headers (CRLF-terminated lines) +
  body. A Content-Length is added automatically when body <> ''. }
function HttpExec(const method, url, extraHeaders, body: AnsiString): THttpResponse;

{ GET following up to maxRedirects 3xx Location hops (absolute Location URLs).
  Returns the final response (or the last 3xx if the limit is hit). }
function HttpGetFollow(const url: AnsiString; maxRedirects: Integer): THttpResponse;

{ --- keep-alive: a reusable connection (blocking) ---
  HttpConnect opens a connection; HttpConnExec/HttpConnGet send a request with
  `Connection: keep-alive` and read exactly ONE response (length-aware: exactly
  Content-Length bytes, or the full chunked body), leaving the socket open and
  any surplus bytes buffered for the next request. conn.Alive goes False if the
  server closes (or asks to). HttpConnClose closes the socket. }
type
  THttpConnection = record
    Sock:  TNetSocket;
    Host:  AnsiString;
    Port:  Integer;
    Buf:   AnsiString;     { bytes read past the current response, kept for next }
    Alive: Boolean;
    IsTls: Boolean;        { https — I/O routed through the TLS seam (tls.pas) }
    Tls:   TTlsConn;       { backend connection handle when IsTls }
  end;

function HttpConnect(const host: AnsiString; port: Integer; isTls: Boolean): THttpConnection;
function HttpConnExec(var conn: THttpConnection; const method, path, extraHeaders, body: AnsiString): THttpResponse;
function HttpConnGet(var conn: THttpConnection; const path: AnsiString): THttpResponse;
procedure HttpConnClose(var conn: THttpConnection);

{ Async keep-alive (call from a coroutine; same THttpConnection, reactor recv). }
function HttpConnectAsync(const host: AnsiString; port: Integer; isTls: Boolean): THttpConnection;
function HttpConnExecAsync(var conn: THttpConnection; const method, path, extraHeaders, body: AnsiString): THttpResponse;
function HttpConnGetAsync(var conn: THttpConnection; const path: AnsiString): THttpResponse;

{ --- async transport (call from inside a coroutine; drive with RunUntilDone) ---
  Non-blocking connect/send/recv over the scheduler's epoll reactor (via
  asyncnet): the coroutine yields on EAGAIN, so one thread serves many requests.
  Hostnames resolve via the async resolver (dns_async); reuses the same pure
  build/parse helpers. }
function HttpGetAsync(const url: AnsiString): THttpResponse;
function HttpPostAsync(const url, contentType, body: AnsiString): THttpResponse;
{ Async GET following up to maxRedirects 3xx Location hops (absolute URLs). }
function HttpGetFollowAsync(const url: AnsiString; maxRedirects: Integer): THttpResponse;

{ --- connection pool (concurrency-safe across coroutines) ---
  HttpGetPooled / HttpGetPooledAsync transparently reuse a live keep-alive
  connection to the same host:port:scheme from a process-global pool, opening a
  fresh one only when no free one is available (then keeping it for next time).
  Each in-flight request reserves its slot (InUse), so two coroutines hitting the
  same host never share a socket; exec runs on a local copy written back by slot
  index, so another coroutine's pool growth can't dangle a `var` across a reactor
  yield. HttpPoolClose closes and drops every pooled connection. }
function HttpGetPooled(const url: AnsiString): THttpResponse;
function HttpGetPooledAsync(const url: AnsiString): THttpResponse;
procedure HttpPoolClose;

{ Idle eviction: close every free (not-InUse) connection idle for >= maxIdleMs
  (monotonic). Call periodically from the reactor flow. }
procedure HttpPoolEvictIdle(maxIdleMs: Int64);
{ Number of live (still-open) pooled connections — observability / tests. }
function HttpPoolCount: Integer;

{ Explicit acquire/exec/release — pin one connection across several requests,
  concurrency-safe. Acquire reserves a live free slot (or opens fresh), returning
  a slot handle (>= 0) or -1 on connect failure. Exec sends one keep-alive
  request on the handle. Release frees the slot (closing it if it died). }
function HttpPoolAcquire(const host: AnsiString; port: Integer; isTls, async: Boolean): Integer;
function HttpPoolSlotExec(handle: Integer;
  const method, path, extraHeaders, body: AnsiString; async: Boolean): THttpResponse;
procedure HttpPoolReleaseSlot(handle: Integer);

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

function HttpParseHeaders(const block: AnsiString): THttpHeaders;
var
  arr: array of THttpHeaderPair;
  cnt, i, n, lineStart, colon: Integer;
  line, nm: AnsiString;
begin
  cnt := 0;
  n := Length(block);
  lineStart := 1;
  for i := 1 to n + 1 do
    if (i > n) or (block[i] = #10) then
    begin
      line := Copy(block, lineStart, i - lineStart);
      if (Length(line) > 0) and (line[Length(line)] = #13) then
        line := Copy(line, 1, Length(line) - 1);
      colon := Pos(':', line);
      if colon > 0 then
      begin
        nm := Trim(Copy(line, 1, colon - 1));
        if nm <> '' then
        begin
          SetLength(arr, cnt + 1);          { local array — SetLength OK }
          arr[cnt].Name := nm;
          arr[cnt].Value := Trim(Copy(line, colon + 1, Length(line)));
          cnt := cnt + 1;
        end;
      end;
      lineStart := i + 1;
    end;
  Result.List := arr;
  Result.Count := cnt;
end;

function HttpHeadersGet(const h: THttpHeaders; const name: AnsiString): AnsiString;
var i: Integer; ln: AnsiString;
begin
  Result := '';
  ln := LowerCase(name);
  for i := 0 to h.Count - 1 do
    if LowerCase(h.List[i].Name) = ln then begin Result := h.List[i].Value; Exit; end;
end;

function HttpHeadersHas(const h: THttpHeaders; const name: AnsiString): Boolean;
var i: Integer; ln: AnsiString;
begin
  Result := False;
  ln := LowerCase(name);
  for i := 0 to h.Count - 1 do
    if LowerCase(h.List[i].Name) = ln then begin Result := True; Exit; end;
end;

function HttpHeaderName(const h: THttpHeaders; i: Integer): AnsiString;
begin
  if (i >= 0) and (i < h.Count) then Result := h.List[i].Name else Result := '';
end;

function HttpHeaderVal(const h: THttpHeaders; i: Integer): AnsiString;
begin
  if (i >= 0) and (i < h.Count) then Result := h.List[i].Value else Result := '';
end;

function HttpResponseHeaders(const resp: THttpResponse): THttpHeaders;
begin
  Result := HttpParseHeaders(resp.Headers);
end;

function HttpResponseHeader(const resp: THttpResponse; const name: AnsiString): AnsiString;
begin
  Result := HttpHeaderValue(resp.Headers, name);
end;

function HttpHexVal(const s: AnsiString): Integer;
var k, d: Integer; c: Char;
begin
  Result := 0;
  for k := 1 to Length(s) do
  begin
    c := s[k];
    if (c >= '0') and (c <= '9') then d := Ord(c) - Ord('0')
    else if (c >= 'a') and (c <= 'f') then d := Ord(c) - Ord('a') + 10
    else if (c >= 'A') and (c <= 'F') then d := Ord(c) - Ord('A') + 10
    else Break;       { stop at ';' chunk-ext or whitespace }
    Result := Result * 16 + d;
  end;
end;

function HttpHexDigit(n: Integer): Char;
begin
  if n < 10 then Result := Chr(Ord('0') + n)
  else Result := Chr(Ord('A') + n - 10);
end;

function HttpUrlEncode(const s: AnsiString): AnsiString;
var i, o: Integer; c: Char; r: AnsiString;
begin
  r := '';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if ((c >= 'A') and (c <= 'Z')) or ((c >= 'a') and (c <= 'z')) or
       ((c >= '0') and (c <= '9')) or (c = '-') or (c = '_') or (c = '.') or (c = '~') then
      r := r + c
    else
    begin
      o := Ord(c);
      r := r + '%' + HttpHexDigit(o div 16) + HttpHexDigit(o mod 16);
    end;
  end;
  Result := r;
end;

function HttpUrlDecode(const s: AnsiString): AnsiString;
var i, n: Integer; c: Char; r: AnsiString;
begin
  r := ''; i := 1; n := Length(s);
  while i <= n do
  begin
    c := s[i];
    if (c = '%') and (i + 2 <= n) then
    begin
      r := r + Chr(HttpHexVal(Copy(s, i + 1, 2)));
      i := i + 3;
    end
    else if c = '+' then begin r := r + ' '; i := i + 1; end
    else begin r := r + c; i := i + 1; end;
  end;
  Result := r;
end;

function HttpQueryAdd(const q, name, value: AnsiString): AnsiString;
begin
  Result := HttpUrlEncode(name) + '=' + HttpUrlEncode(value);
  if q <> '' then Result := q + '&' + Result;
end;

function HttpDechunk(const body: AnsiString): AnsiString;
var
  pos, n, sz: Integer;
  hexline, outp: AnsiString;
  lineEnd: Integer;
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
    sz := HttpHexVal(hexline);
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

{ ===== TLS-aware transport seam =====
  All HTTP byte I/O funnels through these so the same protocol code serves plain
  and https. When isTls, bytes go through the active TLS backend (tls.pas); else
  the plain blocking (Net*) or reactor (Tcp*) transport. With no backend
  registered, an https request fails cleanly (HttpTlsConnect returns False ->
  caller returns Ok=False) rather than crashing.

  Handshake is treated as completing within one TlsHandshake call (the mock and a
  blocking OpenSSL backend do; a future fully-async handshake will need a resume
  step added to the seam). The want-read/want-write retry loop lives on the data
  path (Read/Write), where it is resumable on the same connection and where async
  yielding actually matters. }

procedure HttpIoWait(fd: Integer; async, forRead: Boolean);
begin
  if async then
  begin
    if forRead then WaitReadable(fd) else WaitWritable(fd);
  end
  else if forRead then PalPoll(fd, PAL_POLL_IN, -1)
  else PalPoll(fd, PAL_POLL_OUT, -1);
end;

{ Client TLS handshake over a connected fd. Drives the seam's non-blocking
  handshake to completion: on want-read/want-write it waits for the fd (blocking
  poll or async coroutine yield) and resumes. True on tlsOk; False (cleanly) when
  no backend or the handshake failed. }
function HttpTlsConnect(fd: Integer; const host: AnsiString; async: Boolean;
                        var tlsc: TTlsConn): Boolean;
var r: TTlsResult;
begin
  tlsc := nil;
  Result := False;
  if not TlsAvailable then Exit;
  r := TlsHandshake(fd, tlsClient, host, tlsc);
  while (r = tlsWantRead) or (r = tlsWantWrite) do
  begin
    HttpIoWait(fd, async, r = tlsWantRead);
    r := TlsHandshakeResume(tlsc);
  end;
  Result := r = tlsOk;
  if not Result and (tlsc <> nil) then
  begin
    TlsClose(tlsc); tlsc := nil;
  end;
end;

{ Send the whole buffer. Plain path matches the old single-call behaviour; TLS
  path loops over partial writes and want-states. }
function HttpSendAll(fd: Integer; tlsc: TTlsConn; isTls, async: Boolean;
                     buf: Pointer; len: Integer): Boolean;
var off, put: Integer; r: TTlsResult; n: Int64;
begin
  if isTls then
  begin
    off := 0;
    while off < len do
    begin
      r := TlsWrite(tlsc, Pointer(Int64(buf) + off), len - off, put);
      if r = tlsOk then off := off + put
      else if r = tlsWantWrite then HttpIoWait(fd, async, False)
      else if r = tlsWantRead then HttpIoWait(fd, async, True)
      else begin Result := False; Exit; end;
    end;
    Result := True;
  end
  else
  begin
    if async then n := TcpSend(fd, buf, len) else n := NetSend(fd, buf, len);
    Result := n >= 0;
  end;
end;

{ One read. Returns bytes (>0), 0 on clean close, <0 on error — same convention
  as Net/TcpRecv, so existing read loops are unchanged. }
function HttpRecvSome(fd: Integer; tlsc: TTlsConn; isTls, async: Boolean;
                      buf: Pointer; len: Integer): Int64;
var got: Integer; r: TTlsResult;
begin
  if isTls then
  begin
    repeat
      r := TlsRead(tlsc, buf, len, got);
      if r = tlsWantRead then HttpIoWait(fd, async, True)
      else if r = tlsWantWrite then HttpIoWait(fd, async, False);
    until (r <> tlsWantRead) and (r <> tlsWantWrite);
    if r = tlsOk then Result := got
    else if r = tlsClosed then Result := 0
    else Result := -1;
  end
  else if async then Result := TcpRecv(fd, buf, len)
  else Result := NetRecv(fd, buf, len);
end;

function HttpRequest(const method, url, extraHeaders, body: AnsiString): THttpResponse;
var
  host, path: AnsiString;
  port: Integer;
  isTls: Boolean;
  ip: LongWord;
  sock: TNetSocket;
  tlsc: TTlsConn;
  req, raw: AnsiString;
  buf: array[0..4095] of Byte;
  n, old: Integer;
const
  BUFSZ = 4096;
begin
  Result.Ok := False; Result.Status := 0; Result.Reason := '';
  Result.Headers := ''; Result.Body := '';

  tlsc := nil;
  if not HttpParseUrl(url, host, port, path, isTls) then Exit;
  if not HttpResolve(host, ip) then Exit;

  sock := NetTcpConnect(NetAddress(ip, port));
  if sock < 0 then Exit;

  if isTls and not HttpTlsConnect(sock, host, False, tlsc) then
  begin
    NetClose(sock); Exit;             { https requested but no/failed TLS backend }
  end;

  req := HttpBuildRequest(method, host, path, extraHeaders, body);
  if not HttpSendAll(sock, tlsc, isTls, False, @req[1], Length(req)) then
  begin
    if isTls then TlsClose(tlsc);
    NetClose(sock); Exit;
  end;

  raw := '';
  repeat
    n := HttpRecvSome(sock, tlsc, isTls, False, @buf[0], BUFSZ);
    if n > 0 then
    begin
      old := Length(raw);
      SetLength(raw, old + n);
      Move(buf[0], raw[old + 1], n);          { bulk append — not per-byte }
    end;
  until n <= 0;
  if isTls then TlsClose(tlsc);
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

function HttpPostForm(const url, formBody: AnsiString): THttpResponse;
begin
  Result := HttpPost(url, 'application/x-www-form-urlencoded', formBody);
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

{ ---- keep-alive helpers ---- }

{ 1-based position of the first CRLFCRLF in s, or 0. }
function HttpFindHeaderEnd(const s: AnsiString): Integer;
var i, n: Integer;
begin
  Result := 0;
  n := Length(s);
  for i := 1 to n - 3 do
    if (s[i] = #13) and (s[i+1] = #10) and (s[i+2] = #13) and (s[i+3] = #10) then
    begin Result := i; Exit; end;
end;

{ Byte length of a COMPLETE chunked body in s starting at `start` (1-based),
  through the terminating empty line; -1 if not all present yet. }
function HttpChunkedLen(const s: AnsiString; start: Integer): Integer;
var pos, n, sz, lineEnd: Integer;
begin
  pos := start; n := Length(s);
  while pos <= n do
  begin
    lineEnd := pos;
    while (lineEnd < n) and not ((s[lineEnd] = #13) and (s[lineEnd+1] = #10)) do Inc(lineEnd);
    if (lineEnd >= n) or not ((s[lineEnd] = #13) and (s[lineEnd+1] = #10)) then
    begin Result := -1; Exit; end;          { size line's CRLF not here yet }
    sz := HttpHexVal(Copy(s, pos, lineEnd - pos));
    pos := lineEnd + 2;                       { past the size CRLF }
    if sz = 0 then
    begin
      { final chunk: need the terminating CRLF (no trailers supported). }
      if (pos + 1 <= n) and (s[pos] = #13) and (s[pos+1] = #10) then
        Result := (pos + 1) - start + 1
      else
        Result := -1;
      Exit;
    end;
    if pos + sz + 2 - 1 > n then begin Result := -1; Exit; end;  { data+CRLF not all here }
    pos := pos + sz + 2;                       { data + trailing CRLF }
  end;
  Result := -1;
end;

{ One recv (blocking NetRecv, or reactor TcpRecv when async) appended to
  conn.Buf; returns the byte count (0 = peer closed). }
function HttpConnRecvMore(var conn: THttpConnection; async: Boolean): Integer;
var b: array[0..4095] of Byte; got: Int64; n, oldLen: Integer;
begin
  got := HttpRecvSome(conn.Sock, conn.Tls, conn.IsTls, async, @b[0], 4096);
  if got > 0 then
  begin
    n := Integer(got);
    oldLen := Length(conn.Buf);
    SetLength(conn.Buf, oldLen + n);        { grow the field in place (needs the
                                              v67 var-param-field SetLength fix) }
    Move(b[0], conn.Buf[oldLen + 1], n);
  end
  else
    conn.Alive := False;
  Result := Integer(got);
end;

function HttpConnect(const host: AnsiString; port: Integer; isTls: Boolean): THttpConnection;
var ip: LongWord;
begin
  Result.Host := host; Result.Port := port; Result.Buf := '';
  Result.Sock := NET_INVALID_SOCKET; Result.Alive := False;
  Result.IsTls := isTls; Result.Tls := nil;
  if not HttpResolve(host, ip) then Exit;
  Result.Sock := NetTcpConnect(NetAddress(ip, port));
  if Result.Sock < 0 then Exit;
  if isTls and not HttpTlsConnect(Result.Sock, host, False, Result.Tls) then
  begin
    NetClose(Result.Sock); Result.Sock := NET_INVALID_SOCKET; Exit;
  end;
  Result.Alive := True;
end;

{ Shared core: send a keep-alive request and read exactly one length-aware
  response. async picks the reactor (TcpRecv/TcpSend) vs blocking (Net*). }
function HttpConnExecCore(var conn: THttpConnection;
  const method, path, extraHeaders, body: AnsiString; async: Boolean): THttpResponse;
var
  req, headerBlock, oneResp: AnsiString;
  hdrEnd, bodyStart, clen, clen2, blen: Integer;
begin
  Result.Ok := False; Result.Status := 0; Result.Reason := '';
  Result.Headers := ''; Result.Body := '';
  if not conn.Alive then Exit;

  { keep-alive request: like HttpBuildRequest but Connection: keep-alive. }
  req := method + ' ' + path + ' HTTP/1.1' + CRLF + 'Host: ' + conn.Host + CRLF +
         'Connection: keep-alive' + CRLF + extraHeaders;
  if body <> '' then req := req + 'Content-Length: ' + IntToStr(Length(body)) + CRLF;
  req := req + CRLF;
  if body <> '' then req := req + body;
  if not HttpSendAll(conn.Sock, conn.Tls, conn.IsTls, async, @req[1], Length(req)) then
  begin conn.Alive := False; Exit; end;

  { read until the full header block is buffered }
  hdrEnd := HttpFindHeaderEnd(conn.Buf);
  while hdrEnd = 0 do
  begin
    if HttpConnRecvMore(conn, async) <= 0 then Exit;   { closed before full headers }
    hdrEnd := HttpFindHeaderEnd(conn.Buf);
  end;
  headerBlock := Copy(conn.Buf, 1, hdrEnd - 1);
  bodyStart := hdrEnd + 4;

  { length-aware: exactly Content-Length, or the full chunked body }
  if Pos('chunked', LowerCase(HttpHeaderValue(headerBlock, 'Transfer-Encoding'))) > 0 then
  begin
    blen := HttpChunkedLen(conn.Buf, bodyStart);
    while blen < 0 do
    begin
      if HttpConnRecvMore(conn, async) <= 0 then Break;
      blen := HttpChunkedLen(conn.Buf, bodyStart);
    end;
    if blen < 0 then Exit;
  end
  else
  begin
    clen := StrToIntDef(HttpHeaderValue(headerBlock, 'Content-Length'), 0);
    blen := clen;
    while (Length(conn.Buf) - (bodyStart - 1)) < clen do
      if HttpConnRecvMore(conn, async) <= 0 then Break;
    clen2 := Length(conn.Buf) - (bodyStart - 1);
    if clen2 < blen then blen := clen2;        { short close — take what we got }
  end;

  { this response = headers + its body; the rest stays buffered for the next. }
  oneResp := Copy(conn.Buf, 1, (bodyStart - 1) + blen);
  conn.Buf := Copy(conn.Buf, bodyStart + blen, Length(conn.Buf));
  HttpParseResponse(oneResp, Result);

  if Pos('close', LowerCase(HttpHeaderValue(headerBlock, 'Connection'))) > 0 then
    conn.Alive := False;
end;

function HttpConnExec(var conn: THttpConnection; const method, path, extraHeaders, body: AnsiString): THttpResponse;
begin
  Result := HttpConnExecCore(conn, method, path, extraHeaders, body, False);
end;

function HttpConnGet(var conn: THttpConnection; const path: AnsiString): THttpResponse;
begin
  Result := HttpConnExecCore(conn, 'GET', path, '', '', False);
end;

procedure HttpConnClose(var conn: THttpConnection);
var rc: Integer;
begin
  if conn.IsTls then begin TlsClose(conn.Tls); conn.Tls := nil; end;
  if conn.Sock >= 0 then rc := NetClose(conn.Sock);
  conn.Sock := NET_INVALID_SOCKET;
  conn.Alive := False;
  conn.Buf := '';
end;

function HttpConnExecAsync(var conn: THttpConnection; const method, path, extraHeaders, body: AnsiString): THttpResponse;
begin
  Result := HttpConnExecCore(conn, method, path, extraHeaders, body, True);
end;

function HttpConnGetAsync(var conn: THttpConnection; const path: AnsiString): THttpResponse;
begin
  Result := HttpConnExecCore(conn, 'GET', path, '', '', True);
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

function HttpConnectAsync(const host: AnsiString; port: Integer; isTls: Boolean): THttpConnection;
var ip: LongWord;
begin
  Result.Host := host; Result.Port := port; Result.Buf := '';
  Result.Sock := NET_INVALID_SOCKET; Result.Alive := False;
  Result.IsTls := isTls; Result.Tls := nil;
  if not HttpResolveAsync(host, ip) then Exit;
  Result.Sock := TcpConnectAddr(ip, port);
  if Result.Sock < 0 then Exit;
  if isTls and not HttpTlsConnect(Result.Sock, host, True, Result.Tls) then
  begin
    TcpClose(Result.Sock); Result.Sock := NET_INVALID_SOCKET; Exit;
  end;
  Result.Alive := True;
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
  n, old: Integer;
  tlsc: TTlsConn;
const
  BUFSZ = 4096;
begin
  Result.Ok := False; Result.Status := 0; Result.Reason := '';
  Result.Headers := ''; Result.Body := '';

  tlsc := nil;
  if not HttpParseUrl(url, host, port, path, isTls) then Exit;
  if not HttpResolveAsync(host, ip) then Exit; { dotted-quad or hostname, async }

  fd := TcpConnectAddr(ip, port);              { yields until connected }
  if fd < 0 then Exit;

  if isTls and not HttpTlsConnect(fd, host, True, tlsc) then
  begin
    TcpClose(fd); Exit;                        { https requested but no/failed TLS backend }
  end;

  req := HttpBuildRequest(method, host, path, extraHeaders, body);
  if not HttpSendAll(fd, tlsc, isTls, True, @req[1], Length(req)) then
  begin
    if isTls then TlsClose(tlsc);
    TcpClose(fd); Exit;
  end;

  raw := '';
  repeat
    n := HttpRecvSome(fd, tlsc, isTls, True, @buf[0], BUFSZ);   { yields on EAGAIN }
    if n > 0 then
    begin
      old := Length(raw);
      SetLength(raw, old + n);
      Move(buf[0], raw[old + 1], n);          { bulk append — not per-byte }
    end;
  until n <= 0;
  if isTls then TlsClose(tlsc);
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

type
  THttpPoolSlot = record
    Conn:     THttpConnection;
    InUse:    Boolean;       { reserved by an in-flight request — never shared }
    LastUsed: Int64;         { PalMonotonicMillis at last release — idle eviction }
  end;
var
  gPool: array of THttpPoolSlot;

{ Reserve a free, live slot to host:port:scheme (mark InUse). -1 if none free. }
function HttpPoolReserve(const host: AnsiString; port: Integer; isTls: Boolean): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to Length(gPool) - 1 do
    if (not gPool[i].InUse) and gPool[i].Conn.Alive
       and (gPool[i].Conn.Port = port) and (gPool[i].Conn.Host = host)
       and (gPool[i].Conn.IsTls = isTls) then
    begin
      gPool[i].InUse := True;
      Result := i; Exit;
    end;
end;

function HttpPoolAcquire(const host: AnsiString; port: Integer; isTls, async: Boolean): Integer;
var idx, i, n: Integer; c: THttpConnection;
begin
  idx := HttpPoolReserve(host, port, isTls);     { a live free slot, now InUse }
  if idx >= 0 then begin Result := idx; Exit; end;

  if async then c := HttpConnectAsync(host, port, isTls)
  else           c := HttpConnect(host, port, isTls);
  if not c.Alive then begin HttpConnClose(c); Result := -1; Exit; end;

  { park the fresh connection in a dead free slot, else append — reserved InUse }
  for i := 0 to Length(gPool) - 1 do
    if (not gPool[i].InUse) and (not gPool[i].Conn.Alive) then
    begin
      gPool[i].Conn := c; gPool[i].InUse := True;
      gPool[i].LastUsed := PalMonotonicMillis;
      Result := i; Exit;
    end;
  n := Length(gPool);
  SetLength(gPool, n + 1);            { gPool is a global — SetLength OK }
  gPool[n].Conn := c; gPool[n].InUse := True;
  gPool[n].LastUsed := PalMonotonicMillis;
  Result := n;
end;

function HttpPoolSlotExec(handle: Integer;
  const method, path, extraHeaders, body: AnsiString; async: Boolean): THttpResponse;
var c: THttpConnection;
begin
  Result.Ok := False; Result.Status := 0; Result.Reason := '';
  Result.Headers := ''; Result.Body := '';
  if (handle < 0) or (handle >= Length(gPool)) then Exit;
  c := gPool[handle].Conn;             { local copy — survives a reactor yield even
                                         if another coroutine grows gPool }
  Result := HttpConnExecCore(c, method, path, extraHeaders, body, async);
  gPool[handle].Conn := c;             { write the updated state back by index }
  gPool[handle].LastUsed := PalMonotonicMillis;
end;

procedure HttpPoolReleaseSlot(handle: Integer);
begin
  if (handle < 0) or (handle >= Length(gPool)) then Exit;
  if not gPool[handle].Conn.Alive then
    HttpConnClose(gPool[handle].Conn);  { dead — free the fd; slot reusable }
  gPool[handle].InUse := False;
  gPool[handle].LastUsed := PalMonotonicMillis;
end;

function HttpGetPooledCore(const url: AnsiString; async: Boolean): THttpResponse;
var host, path: AnsiString; port, h: Integer; isTls: Boolean;
begin
  Result.Ok := False; Result.Status := 0; Result.Reason := '';
  Result.Headers := ''; Result.Body := '';
  if not HttpParseUrl(url, host, port, path, isTls) then Exit;

  h := HttpPoolAcquire(host, port, isTls, async);
  if h < 0 then Exit;                  { connect failed }
  Result := HttpPoolSlotExec(h, 'GET', path, '', '', async);

  { a pooled connection the server had silently dropped: retry once, fresh }
  if (not Result.Ok) and (not gPool[h].Conn.Alive) then
  begin
    HttpPoolReleaseSlot(h);            { closes the dead one, frees the slot }
    h := HttpPoolAcquire(host, port, isTls, async);   { opens fresh (dead skipped) }
    if h < 0 then Exit;
    Result := HttpPoolSlotExec(h, 'GET', path, '', '', async);
  end;
  HttpPoolReleaseSlot(h);
end;

function HttpGetPooled(const url: AnsiString): THttpResponse;
begin Result := HttpGetPooledCore(url, False); end;

function HttpGetPooledAsync(const url: AnsiString): THttpResponse;
begin Result := HttpGetPooledCore(url, True); end;

procedure HttpPoolEvictIdle(maxIdleMs: Int64);
var i: Integer; now: Int64;
begin
  now := PalMonotonicMillis;
  for i := 0 to Length(gPool) - 1 do
    if (not gPool[i].InUse) and gPool[i].Conn.Alive
       and ((now - gPool[i].LastUsed) >= maxIdleMs) then
      HttpConnClose(gPool[i].Conn);   { mark dead; the slot is reused later }
end;

function HttpPoolCount: Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to Length(gPool) - 1 do
    if gPool[i].Conn.Alive then Inc(Result);
end;

procedure HttpPoolClose;
var i: Integer;
begin
  for i := 0 to Length(gPool) - 1 do
    HttpConnClose(gPool[i].Conn);
  SetLength(gPool, 0);
end;

end.
