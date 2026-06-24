# Own networking library — native HTTP client (+ sockets, async)

- **Type:** feature (library) — our own net stack, independent of Synapse
- **Status:** working (first slices landed)
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
- `TStream` / `TMemoryStream` — written, **blocked** on two Track A gaps:
  [[bug-read-write-reserved-as-method-names]] and [[bug-untyped-params-in-methods]]
  (both needed for the standard `Read`/`Write(var Buffer; …)` surface). Synapse's
  heaviest Classes need.

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

## Roadmap (next slices)

1. Concurrency-safe pool (per-coroutine acquire/release) + a blocking
   `HttpGetPooled`; pool eviction/idle-timeout.
2. Structured headers on `THttpResponse` (today: raw `.Headers` block; parse via
   `HttpParseHeaders` on demand).
3. **TLS** — `https://` is parsed and refused (`isTls`). Routes through a common
   TLS seam [[feature-tls-provider-abstraction]] with two interchangeable
   backends: OpenSSL (default; via [[feature-real-dynlib-loader]]) and the native
   handrolled stack [[feature-tls13-from-scratch]]. Mix-and-match (e.g. native
   client ⇄ OpenSSL server) is the interop correctness test.

## Compiler gaps surfaced while building (filed)

- [[bug-pointer-deref-not-accepted-as-var-arg]] — `p^` rejected as a var arg
  (worked around in `fpSelect`).
- `SizeOf(var)` not supported — only `SizeOf(TypeName)` (used type names /
  explicit size constants in `sockets`/`http`). Minor; file if it recurs.

## Done when

The native lib offers: blocking + async HTTP GET/POST against real servers,
Content-Length/chunked framing, a clean address/socket layer, all smoked under
`make lib-test`. TLS tracked but may land separately.
