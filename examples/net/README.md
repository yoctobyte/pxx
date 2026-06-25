# examples/net — native networking showcase

`httpdemo.pas` is a self-contained demo of frank2's native networking library
(`lib/rtl/http.pas` and friends) — no external network needed. A loopback HTTP
server and client run as coroutines on one reactor thread.

```
pxx -Fulib/rtl/platform/posix examples/net/httpdemo.pas /tmp/httpdemo && /tmp/httpdemo
```

It exercises, over a single keep-alive connection: a routing server handler
(`HttpServeConn`), a cookie round-trip, and transparent gzip decoding.

## The library at a glance

Everything below builds against the pinned stable compiler — the net library
never needs the compiler rebuilt.

### Client (`uses http`)

```pascal
r := HttpGet('http://example.com/');          // blocking
writeln(r.Status, ' ', r.Reason, ' ', r.Body);

// async (call from a coroutine, drive with RunUntilDone)
r := HttpGetAsync('http://127.0.0.1:8080/');
```

- Methods: `HttpGet/Post/Head/Put/Delete`, generic `HttpExec(method, url, headers, body)`.
- Redirects: `HttpGetFollow` / `HttpGetFollowAsync`.
- Keep-alive: `HttpConnect` + `HttpConnExec`; a concurrency-safe pool via
  `HttpGetPooled` / `HttpGetPooledAsync` (`HttpPoolSetMaxPerHost`,
  `HttpPoolEvictIdle`).
- Bodies: `Content-Encoding: gzip`/`deflate` is decoded automatically; the
  client advertises `Accept-Encoding`.
- Helpers: `HttpBasicAuth`, the multipart builder (`HttpMultipart*`), the cookie
  jar (`HttpCookie*`), URL/query helpers (`HttpUrlEncode`, `HttpQueryAdd/Get/Has`).
- `https://` routes through the TLS seam (`tls.pas`; OpenSSL backend in
  `tls_openssl.pas`).

### Server (`uses http`)

```pascal
function Handler(const req: THttpRequest): AnsiString;
begin
  if req.Path = '/' then
    Handler := HttpBuildResponse(200, 'OK', '', 'hello')
  else
    Handler := HttpBuildResponse(404, 'Not Found', '', 'nope');
end;

// in a coroutine: accept, then run the per-connection serve loop
cfd := TcpAccept(lfd);
HttpServeConn(cfd, @Handler, 0, True);   // 0 = serve until the peer closes
```

`HttpParseRequest` / `HttpRequestHeader` / `HttpBuildResponse` (auto
Content-Length) are the pieces; `HttpServeConn` ties them into the read →
dispatch → send keep-alive loop.

### JSON over HTTP (`uses httpjson`)

```pascal
v := HttpGetJsonAsync('http://127.0.0.1:8080/api', ok);   // -> TJSONValue
if ok then writeln(v.GetValue('name').AsString);
v.FreeTree;
```

## Portability

The source is portable: it builds on `amd64` (primary) and `aarch64`. `i386` and
`arm32` are currently blocked on backend gaps — see the Track A ticket
`feature-net-lib-cross-target`.
