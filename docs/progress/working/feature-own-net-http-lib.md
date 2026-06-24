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
- Caveat: async DNS not yet wired — `HttpGetAsync` is dotted-quad only (a
  hostname fails); blocking `HttpGet` resolves names. True async DNS is a slice.

## Roadmap (next slices)

1. **Async DNS** — resolve over UDP on the reactor so `HttpGetAsync` takes
   hostnames (today dotted-quad only).
2. **Response framing breadth** — `Content-Length` bodies and chunked transfer
   encoding (today: read-to-EOF with `Connection: close`); keep-alive.
4. **TLS** — `https://` is parsed and refused (`isTls`); needs a TLS layer
   (separate unit; ties into [[feature-real-dynlib-loader]] only if we shell out
   to OpenSSL, otherwise a from-scratch/ BearSSL-style stack — design later).
5. **More methods / headers API** — PUT/DELETE/HEAD, a small header map, redirects.

## Compiler gaps surfaced while building (filed)

- [[bug-pointer-deref-not-accepted-as-var-arg]] — `p^` rejected as a var arg
  (worked around in `fpSelect`).
- `SizeOf(var)` not supported — only `SizeOf(TypeName)` (used type names /
  explicit size constants in `sockets`/`http`). Minor; file if it recurs.

## Done when

The native lib offers: blocking + async HTTP GET/POST against real servers,
Content-Length/chunked framing, a clean address/socket layer, all smoked under
`make lib-test`. TLS tracked but may land separately.
