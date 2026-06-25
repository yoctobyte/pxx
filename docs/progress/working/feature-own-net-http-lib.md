# Own networking library — native HTTP client (+ sockets, async)

- **Type:** feature (library) — our own net stack, independent of Synapse
- **Status:** working (Track B — client feature-complete for common use: pool
  (concurrent+cap), gzip/deflate, Accept-Encoding, base64+Basic auth, multipart,
  cookie jar, all e2e-proven; next: example/demo app)
- **Owner:** — (**Track B** — `lib/rtl`, `$(PXX_STABLE)`)
- **Opened:** 2026-06-24
- **Why:** compiling Synapse is nice, but we also want a small, native,
  async-aware net library with HTTP — not tied to Synapse's reused units (whose
  HTTP path is Track-A-blocked on the directive bug anyway). User direction: don't
  tunnel-vision on Synapse when building the socket layer.

## Landed (2026-06-24)

- **`lib/rtl/sockets.pas`** — FPC-compatible Sockets unit (IPv4 core): byte order
  (`htons`/`htonl`/`ntohs`/`ntohl`), `TInetSockAddr` family, AF_/SOCK_/SO_/IP_/
  MSG_ constants, `fp*` (Socket/Bind/Connect/Listen/Accept/Send/Recv/SendTo/
  RecvFrom/Shutdown/GetSockName/CloseSocket) over the PAL IPv4 primitives, and
  `FD_*` + `fpSelect` over PAL ppoll. Smoke `test/lib_sockets` (loopback
  round-trip). Doubles as the Synapse `sockets` shim (ssfpc.inc).
- **`lib/rtl/http.pas`** — native HTTP/1.1 client on `net` + `dns`. Pure helpers
  (`HttpParseUrl`/`HttpBuildRequest`/`HttpParseResponse`, I/O-free, the reuse seam
  for an async transport) + blocking `HttpGet`/`HttpPost`. Smoke `test/lib_http`
  (21 pure-helper checks).

Foundation already present and reused: `net.pas` (blocking TCP/UDP + timeouts),
`scheduler.pas` (coroutines + epoll async reactor: `SetNonBlocking`/
`WaitReadable`/`WaitWritable`/`RunUntilDone`), `dns.pas`.

## Async + e2e landed (2026-06-24)

- **`HttpGetAsync`/`HttpPostAsync`** (http.pas) over the scheduler's epoll reactor
  via asyncnet (non-blocking connect/send/recv, coroutine yields on EAGAIN),
  reusing the same pure build/parse helpers. Added `asyncnet.TcpConnectAddr(host,
  port)` (generalised the loopback `TcpConnect`).
- **`test/lib_http_async`** — true end-to-end: a server coroutine and a client
  coroutine (`HttpGetAsync`) on ONE thread, both reactor-driven via `RunUntilDone`,
  real loopback round-trip (status 200 + body). The proof-of-concept for async
  sockets that a blocking client cannot do single-threaded.
- **Async DNS (landed)** — `lib/rtl/dns_async.pas`: `DnsResolveHostAsync` /
  `DnsQueryAAsync` resolve over UDP on the reactor (yield on the socket), same
  wire format as the blocking resolver; resolv.conf/hosts read synchronously.
  `HttpGetAsync` now takes hostnames (was dotted-quad only). Smoke
  `test/lib_dns_async` — a loopback UDP DNS-server coroutine answers a canned A
  record, client resolves through the reactor (server + client, one thread).
  Pending: TC→TCP retry; multi-nameserver failover on the async path.

## Framing breadth (landed 2026-06-24)

`http.pas` pure helpers: `HttpHeaderValue` (case-insensitive lookup),
`HttpDechunk` (chunked decode), and `HttpParseResponse` now applies framing —
`Transfer-Encoding: chunked` is decoded, else the body is trimmed to
`Content-Length`. Smoke `test/lib_http` (29 checks).

## Methods + redirects (landed 2026-06-24)

Blocking + async method set: `HttpGet/Post/Head/Put/Delete`, generic
`HttpExec(method, url, headers, body)` with custom headers, and
`HttpGetFollow`/`HttpGetFollowAsync` (follow up to N 3xx `Location` hops).
Redirect e2e: `test/lib_http_redirect` — a server coroutine answers 302+Location
then 200, the async client follows the hop (multi-connection, one thread).

## Keep-alive (landed 2026-06-24)

`THttpConnection` (socket + host/port + leftover-byte buffer + Alive) reusable
across requests. `HttpConnect`/`HttpConnExec`/`HttpConnGet` (blocking) and
`HttpConnectAsync`/`HttpConnExecAsync`/`HttpConnGetAsync` (reactor) share one
core: send `Connection: keep-alive`, then **length-aware** read — exactly
Content-Length bytes or the full chunked body (`HttpChunkedLen`), not read-to-EOF
— leaving surplus bytes buffered for the next request. e2e `test/lib_http_keepalive`:
server coroutine does ONE accept and serves TWO requests; client reuses one
connection (both bodies correct, stays Alive between). `HttpConnClose` to finish.

## Classes progress (RTL, drives synapse + general use)

- `TList` / `TStrings` / `TStringList` — **done & smoked** (`lib/rtl/classes.pas`,
  `test/lib_classes`). `TStringList.Sort` blocked on
  [[bug-string-ordering-comparison-constant]].
- `TStream` / `TMemoryStream` — **done & smoked** (Read/Write/Seek/Position/Size/
  CopyFrom). The two Track A gaps that blocked it (Read/Write method names,
  untyped method params) were fixed v54. Minor: bare `Read`/`Write` self-calls in
  a method hit the console intrinsic — qualified with `Self.`
  ([[bug-bare-read-write-in-method-hits-intrinsic]]).

## Header API + URL encoding (landed 2026-06-24)

`THttpHeaders` (name/value pairs) + `HttpParseHeaders` (raw block → structured,
multi-value preserved in order), `HttpHeadersGet`/`HttpHeadersHas`
(case-insensitive), `HttpHeaderName`/`HttpHeaderVal` (iterate). Built locally to
dodge [[bug-setlength-record-field-via-var-param]]. Plus `HttpUrlEncode`/
`HttpUrlDecode` (RFC 3986 percent-encoding; decode also maps `+`→space) for query
strings / form bodies. Pure; `lib_http` now 43 checks.

## Connection pool (landed 2026-06-24)

`HttpGetPooledAsync` transparently reuses a live keep-alive connection to the
same host:port from a process-global pool (opens a fresh one only when none is
free, then keeps it); `HttpPoolClose` drops them all. e2e `test/lib_http_pool`:
server does ONE accept, client makes TWO pooled GETs, the second reuses the
connection. Single-flow (coroutine) only — not concurrency-safe across
simultaneously-running coroutines yet.

## Structured response headers (landed 2026-06-25)

`HttpResponseHeaders(resp): THttpHeaders` (parse the raw `.Headers` block on
demand) + `HttpResponseHeader(resp, name): AnsiString` (case-insensitive single
value) — the convenience seam so callers get structured access without the
response record carrying a `THttpHeaders` field (dodges
[[bug-setlength-record-field-via-var-param]]). Pure forwarders over the existing
`HttpParseHeaders` / `HttpHeaderValue`. `lib_http` now 49 checks (3 added:
`resp-hdrs-count` / `resp-hdr-ci` / `resp-hdr-absent`).

## Concurrency-safe pool (landed 2026-06-25)

The keep-alive pool is now concurrency-safe across coroutines. Each in-flight
request **reserves** its slot (`InUse`), so two coroutines hitting the same
host:port never share a socket; exec runs on a **local copy of the connection
written back by slot index** (`HttpPoolSlotExec`), so another coroutine growing
the global pool (`SetLength`) can't dangle a `var` held across a reactor yield —
the original single-flow-only bug. New API: explicit `HttpPoolAcquire` /
`HttpPoolSlotExec` / `HttpPoolReleaseSlot` (pin a connection across requests),
blocking `HttpGetPooled` (shares `HttpGetPooledCore` with the async path; auto
one-shot retry on a fresh conn if a pooled socket was silently dropped),
`HttpPoolEvictIdle(maxIdleMs)` (close free conns idle past a monotonic
threshold), `HttpPoolCount` (live-conn observability), and
`HttpPoolSetMaxPerHost(n)` (cap idle conns per host:port:scheme; over-cap conns
are closed on release instead of pooled). e2e `test/lib_http_pool_concurrent`:
two client coroutines GET the SAME host:port at once → server must accept TWICE
(proves no socket sharing); with cap=1 only one conn is kept (count=1) →
`HttpPoolEvictIdle(0)` → count=0. `make lib-test` green.

## Content-Encoding: gzip / deflate (landed 2026-06-25)

Responses are now transparently decompressed. `zlib.pas` gained `InflateGzip`
(RFC 1952: parse magic + optional FEXTRA/FNAME/FCOMMENT/FHCRC fields, inflate the
raw deflate body, verify CRC32 + ISIZE) and `InflateRawBytes` (bare RFC 1951, no
wrapper) alongside the existing `InflateZlib` (RFC 1950). `http.pas` gained the
pure `HttpDecodeContent(encoding, body)` — gzip / deflate (zlib-wrapped, with a
raw-deflate fallback) / identity / unknown-passthrough — and `HttpParseResponse`
calls it after framing, so every client path (blocking, async, keep-alive, pool)
gets decoded bodies for free. Tests: `lib_zlib` +3 (`gzip`, `gzip bad crc`, `raw
deflate`), `lib_http` +5 (`ce-identity`/`ce-empty`/`ce-gzip`/`ce-unknown`/
`ce-resp-gzip`, the last a full gzip response decompressed by HttpParseResponse).
`make lib-test` green vs v73.

The client also now **advertises** `Accept-Encoding: gzip, deflate` by default
(via `HttpWithAcceptEncoding`, applied in the three transport sites — blocking,
async, keep-alive — but NOT in the pure `HttpBuildRequest`, and skipped if the
caller already set the header). e2e `test/lib_http_gzip`: a server coroutine
serves a gzip body with `Content-Encoding: gzip`; the async client both
advertises the codec and decodes the body to `hello world` transparently.

## Base64 + HTTP Basic auth (landed 2026-06-25)

New `lib/rtl/base64.pas` — RFC 4648 `Base64Encode`/`Decode` over `TByteArray`
plus `Base64EncodeStr`/`Base64DecodeStr`; decode tolerates ASCII whitespace
(line-wrapped MIME) and rejects invalid chars. Unit test `test/lib_base64` (14
checks: the RFC vectors `f`/`fo`/`foo`/…/`foobar`, padding, whitespace, a full
0..255 byte round-trip, invalid-char rejection). On top, `http.pas`
`HttpBasicAuth(user, pass)` returns a ready `Authorization: Basic <b64>` header
line for the `extraHeaders` arg of `HttpExec`/`HttpConnExec` (`lib_http` +1,
`basic-auth`). `make lib-test` green.

## multipart/form-data builder (landed 2026-06-25)

`http.pas` pure builder for file/field uploads: `HttpMultipartBoundary` (unique
per call), `HttpMultipartContentType(boundary)` (the header line for
`extraHeaders`), `HttpMultipartField`/`HttpMultipartFile` (one RFC 7578 part
each), `HttpMultipartEnd`. Caller concatenates parts and POSTs via `HttpExec`.
`lib_http` +5 (`mp-ctype`/`mp-field`/`mp-file`/`mp-end`/`mp-boundary-uniq`, with
a fixed boundary for deterministic byte assertions). Pure, no I/O. `make
lib-test` green.

## Minimal cookie jar (landed 2026-06-25)

`http.pas` pure cookie helpers over a plain `"a=1; b=2"` jar string (= the Cookie
header value): `HttpCookieSet` (replace/append one pair), `HttpCookieUpdate`
(merge one Set-Cookie value, attributes ignored), `HttpCookieFromResponse`
(merge every `Set-Cookie` header of a response via the structured-headers seam),
`HttpCookieHeader` (render `Cookie: …` request line, empty jar → ''). Tracks
name=value only — Domain/Path/Expires/Secure scoping is out of scope. `lib_http`
+7 (`cookie-set`/`-append`/`-replace`/`-update`/`-header`/`-empty`/`-from-resp`).
`make lib-test` green. e2e `test/lib_http_cookie`: one keep-alive connection, two
requests — the server sets `Set-Cookie` on the first reply, the async client
parses it into a jar and sends it back as a `Cookie` header on the second
request, which the server confirms (`authed`). Composes the cookie jar + async
keep-alive + structured response headers.

## Showcase demo (landed 2026-06-25)

`examples/net/httpdemo.pas` — a self-contained loopback showcase (no external
network): a server coroutine and a client coroutine on one reactor thread, three
requests over a single keep-alive connection — `GET /` (server sets a cookie),
`GET /me` (client sends the cookie back, server greets it), `GET /data.gz` (a
gzip body the client decodes transparently). Prints a deterministic transcript;
smoke `net-demo` in `make lib-test` asserts the 5 key markers.

## Server-side helpers (landed 2026-06-25)

`http.pas` gained the request/response server symmetry of the client helpers:
`THttpRequest` + `HttpParseRequest` (request line → Method/Path/Query/Headers/
Body), `HttpRequestHeader` (case-insensitive lookup), and `HttpBuildResponse`
(status/reason/headers/body, **Content-Length computed automatically**). `lib_http`
+8 (`req-parse`/`-method`/`-path`/`-query`/`-hdr`/`-postbody`, `build-resp`,
`build-resp-empty`). The showcase demo now dogfoods them server-side — dropping
its hand-rolled request parser and hand-counted Content-Lengths (the source of an
earlier off-by-one). `make lib-test` green.

## Query/form read-back (landed 2026-06-25)

`http.pas` `HttpQueryGet(query, name)` / `HttpQueryHas(query, name)` read back an
`a=1&b=2` query or `x-www-form-urlencoded` body — percent-decoded values, names
matched after decoding, `HttpQueryHas` distinguishing present-but-empty from
absent. Completes the form-handling round trip with the existing `HttpQueryAdd`
builder. `lib_http` +8 (`query-get`/`-get-1st`/`-get-miss`/`-decname`/`-has`/
`-has-empty`/`-has-miss`/`-roundtrip`). `make lib-test` green.

## Server framework — HttpServeConn (landed 2026-06-25)

`http.pas` `THttpHandler = function(const req: THttpRequest): AnsiString` +
`HttpServeConn(cfd, handler, maxRequests, async)`: the per-connection serve loop
— length-aware request read (headers + Content-Length body, surplus kept),
dispatch to the user handler (which returns a full response, built via
`HttpBuildResponse`), send, repeat over keep-alive until the peer closes /
`Connection: close` / maxRequests. Reactor or blocking. The caller owns accept.
Turns the server-side helpers into an actual framework: a routing handler in a
few lines. e2e `test/lib_http_serve`: a handler routes on `req.Path`/`req.Query`,
client makes two keep-alive requests (second echoes a query string). `make
lib-test` green.

## Roadmap (next slices)

1. ~~Concurrency-safe pool + blocking `HttpGetPooled` + eviction/idle-timeout~~
   — **landed 2026-06-25** (above), including per-host pool size cap
   (`HttpPoolSetMaxPerHost`).
2. ~~Structured headers on `THttpResponse`~~ — **landed 2026-06-25** (above).
3. **TLS** — seam + http routing **landed 2026-06-25**: `https://` now goes
   through the common TLS seam [[feature-tls-provider-abstraction]]
   (`lib/rtl/tls.pas`) on all four transports (blocking/async one-shot, keep-alive,
   pool); with no backend an https request fails cleanly. Proven plaintext-mock
   e2e (`test/lib_https_mock`, gated `https-mock-seam`). **OpenSSL backend landed
   2026-06-25** (`lib/rtl/tls_openssl.pas`, via the v68 dlopen loader): real
   `HttpGet('https://…')` ⇄ `openssl s_server`, status 200, verified by
   `make tls-openssl-devtest`. **Async TLS landed 2026-06-25** too: the seam
   handshake is non-blocking + resumable (`TlsHandshakeResume`), so `HttpGetAsync`
   over https yields on the reactor and resumes — the devtest now runs both a
   blocking and an async https GET against `openssl s_server`. **Cert
   verification + trust store landed 2026-06-25**: `OpenSslTlsRegister` is now
   secure-by-default (system store + `SSL_VERIFY_PEER` + hostname match via
   `SSL_set1_host`); `OpenSslTlsRegisterEx(verify, caFile)` for private CAs / opt
   out. Devtest proves reject (untrusted self-signed → `Ok=False`) + accept
   (trusted CA → 200) + async. **Server-side TLS landed 2026-06-25**
   (`OpenSslTlsServerInit` + `SSL_accept` via the seam): `devtest_tls_interop`
   runs our OpenSSL HTTPS server ⇄ our verified `HttpGetAsync` client on one
   reactor → 200. The OpenSSL backend is now client+server, blocking+async,
   verified. **Remaining:** the native handrolled stack
   [[feature-tls13-from-scratch]] (deferred) for native⇄OpenSSL interop.

## Compiler gaps surfaced while building (filed)

- [[bug-pointer-deref-not-accepted-as-var-arg]] — `p^` rejected as a var arg
  (worked around in `fpSelect`).
- `SizeOf(var)` not supported — only `SizeOf(TypeName)` (used type names /
  explicit size constants in `sockets`/`http`). Minor; file if it recurs.

## Done when

The native lib offers: blocking + async HTTP GET/POST against real servers,
Content-Length/chunked framing, a clean address/socket layer, all smoked under
`make lib-test`. TLS tracked but may land separately.
