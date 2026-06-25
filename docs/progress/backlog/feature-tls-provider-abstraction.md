# TLS provider abstraction — pluggable backends (OpenSSL + handrolled)

- **Type:** feature (library / architecture) — the TLS seam
- **Status:** backlog
- **Owner:** — (Track B — `lib/rtl`)
- **Opened:** 2026-06-24
- **Relation:** the `https://` enabler for [[feature-own-net-http-lib]]. Umbrella
  over two backends: [[feature-tls13-from-scratch]] (native) and the OpenSSL
  backend (needs [[feature-real-dynlib-loader]]).

## Slice 1 landed — the seam + plumbing proof (2026-06-25)

`lib/rtl/tls.pas` ships the backend-neutral contract: `TTlsRole`, `TTlsResult`
(`tlsOk`/`tlsWantRead`/`tlsWantWrite`/`tlsClosed`/`tlsError`), opaque `TTlsConn`,
and `TTlsBackend` (the vtable: `Name` / `Handshake` / `Read` / `Write` / `Close`).
Plus a process-global registry (`TlsRegisterBackend` / `TlsActiveBackend` /
`TlsAvailable`) and neutral wrappers (`TlsHandshake` / `TlsRead` / `TlsWrite` /
`TlsClose`) that **fail cleanly with `tlsError` when no backend is registered**
(never crash — the `dynlibs`-stub discipline). No backend ships here.

Signature refinement vs the sketch below: `Handshake` returns a `TTlsResult` with
the connection as a `var c: TTlsConn` out-param (uniform with Read/Write error
reporting), rather than returning `TTlsConn` directly.

Plumbing proven by `test/lib_tls` (14 checks, wired into `make lib-test` as
`tls-seam`): the no-backend path refuses cleanly, then a **mock plaintext
backend** (Read/Write just pass bytes over the fd) registered through the seam
carries a real loopback round-trip via `TlsHandshake`/`TlsWrite`/`TlsRead`/
`TlsClose`, and clearing the registry restores the clean state. Exercises the
vtable dispatch + registry independent of any crypto.

## Slice 2 landed — http routes `https://` through the seam (2026-06-25)

`lib/rtl/http.pas` now sends/receives every byte through a TLS-aware transport
funnel (`HttpSendAll` / `HttpRecvSome` / `HttpTlsConnect` / `HttpIoWait`): when a
URL is `https://` it does `TlsHandshake`-after-connect and routes I/O via
`TlsWrite`/`TlsRead`, else the plain blocking (`Net*`) / reactor (`Tcp*`) path
exactly as before. Covers **all four** transports — blocking one-shot
(`HttpRequest`), async one-shot (`HttpRequestAsync`), keep-alive
(`THttpConnection` gained `IsTls`/`Tls`; `HttpConnect`/`HttpConnectAsync` take an
`isTls` arg; close tears the TLS layer down first), and the async pool (reuse
keyed on host:port:**scheme** so an https conn is never handed to a plain request).

The data-path `Read`/`Write` want-loop maps `tlsWantRead`/`tlsWantWrite` to
`WaitReadable`/`WaitWritable` (async) or `PalPoll` (blocking), so a backend that
would-block yields the coroutine and resumes — the async TLS path OpenSSL needs.
The **handshake** is taken as completing within one `TlsHandshake` call (the mock
+ a blocking OpenSSL backend do; a fully-async handshake would need a resume step
added to the seam — noted as future work). With **no backend**, an `https`
request fails cleanly (`Ok=False`) — never crashes.

Proven by `test/lib_https_mock` (6 checks, wired into `make lib-test` as
`https-mock-seam`): no-backend https fails clean, then a mock plaintext backend +
loopback server let `HttpGetAsync('https://...')` complete through the seam over
the reactor (status 200 + body), exercising the want-read yield path. Real
crypto waits on the backends.

## Slice 3 landed — OpenSSL backend, real HTTPS (2026-06-25)

`lib/rtl/tls_openssl.pas` implements `TTlsBackend` over **libssl.so.3, dlopen'd at
runtime** through the real loader ([[feature-real-dynlib-loader]], landed v68).
`OpenSslTlsRegister` loads the lib, resolves `TLS_client_method` / `SSL_CTX_new` /
`SSL_new` / `SSL_set_fd` / `SSL_connect` / `SSL_read` / `SSL_write` /
`SSL_get_error` / `SSL_shutdown` / `SSL_ctrl` (SNI via
`SSL_CTRL_SET_TLSEXT_HOSTNAME`) / frees, builds a client `SSL_CTX`, and registers
itself as the active backend. Entry points are plain (non-cdecl) proc vars — the
x86-64 default ABI matches SysV cdecl for these pointer/int signatures (same as
the `dynlibs` strlen smoke). `SSL_get_error` maps `WANT_READ`/`WANT_WRITE` →
`tlsWantRead`/`tlsWantWrite`, `ZERO_RETURN` → `tlsClosed`.

**Verified end to end:** `make tls-openssl-devtest` (`tools/tls_openssl_devtest.sh`
+ `test/devtest_tls_openssl.pas`) builds the client with `-dPXX_DYNLIB_LIBC`,
spins up a loopback `openssl s_server -www` with a self-signed cert, and a
**blocking `HttpGet('https://…')` returns status 200 + a ~5 KB decrypted body** —
a real TLS 1.3 handshake + GET through our http stack ⇄ OpenSSL. Opt-in /
non-hermetic (needs the openssl CLI + libssl); skips cleanly when absent, so it is
**not** in the core lib-test gate.

## Slice 4 landed — async TLS handshake (2026-06-25)

The seam handshake is now **non-blocking + resumable**: `Handshake` does one step
(allocates the conn, attempts `SSL_connect`) and returns `tlsOk` / `tlsWantRead` /
`tlsWantWrite` / `tlsError`; a new `TTlsBackend.HandshakeResume(c)` (neutral
`TlsHandshakeResume`) does each subsequent step after the fd is ready. `http`'s
`HttpTlsConnect` drives the loop — `HttpIoWait` between steps maps to `PalPoll`
(blocking) or `WaitReadable`/`WaitWritable` (async coroutine yield). A blocking fd
returns `tlsOk` on the first step (loop never runs), so the blocking path is
unchanged; a non-blocking reactor fd yields and resumes.

OpenSSL backend updated accordingly (no internal poll-loop in `Handshake`;
`SslStepConnect` shared by `Handshake`/`HandshakeResume`). **Verified:** the
`tls-openssl-devtest` now runs **both** a blocking `HttpGet` and an async
`HttpGetAsync` (coroutine, `Spawn`/`RunUntilDone`) over real `openssl s_server` —
both return 200 + decrypted body. So HTTPS now composes with the reactor.

## Slice 5 landed — certificate verification + trust store (2026-06-25)

The OpenSSL backend is now **secure by default**. `OpenSslTlsRegister` loads the
system trust store (`SSL_CTX_set_default_verify_paths`), sets
`SSL_VERIFY_PEER`, and per connection calls `SSL_set1_host(host)` so the
handshake validates both the **chain** and the **hostname** (CN/SAN). A failed
verification aborts `SSL_connect` → the request returns `Ok=False`;
`OpenSslTlsLastVerifyResult` exposes the `X509_V_*` code.
`OpenSslTlsRegisterEx(verifyPeer, caFile)` adds a private/test CA on top of the
system store, or turns verification off (dev only).

**Verified** by the extended `tls-openssl-devtest` against `openssl s_server`
(self-signed, CN/SAN=localhost): **reject** — system-store-only, the untrusted
cert is refused (`Ok=False`, `verify_result=18` = self-signed); **accept** — with
the test CA trusted, blocking GET → 200 and the hostname matches; **async** — the
verified connection also works via `HttpGetAsync` on the reactor.

**Next slices:** (a) server side (`SSL_accept`) → the 4-cell client×server interop
matrix; (b) the native backend ([[feature-tls13-from-scratch]], deferred).

## Decision (2026-06-24)

Support **both** TLS backends from the start, behind **one common interface**:

1. **OpenSSL** (dlopen `libssl`/`libcrypto`) — the safe, well-tested, standard
   default. Production path.
2. **Handrolled TLS 1.3 + kTLS** ([[feature-tls13-from-scratch]]) — the platonic,
   syscall-only path; a superb real-world compiler stress test.

Why both, from the get-go (the user's reasoning):
- OpenSSL is the sane/safe default; rolling our own is the compiler test — keep
  both, don't pick.
- A **common seam** lets us **mix and match in one app**: e.g. an HTTP *server*
  on OpenSSL and an HTTP *client* on the native stack (and vice versa). That is
  the proof the abstraction is correct **and** an interop test — our handrolled
  stack must speak real TLS to OpenSSL on the other end, the strongest possible
  correctness check.

## The seam

A backend-neutral TLS connection contract (e.g. `lib/rtl/tls.pas`) that any net
code (`http`, future servers) talks to instead of raw `NetSend`/`NetRecv`:

```
type
  TTlsRole = (tlsClient, tlsServer);
  TTlsResult = (tlsOk, tlsWantRead, tlsWantWrite, tlsClosed, tlsError);

  { A backend = a vtable/class implementing: }
  TTlsBackend = class
    function  Handshake(fd: Integer; role: TTlsRole; const host: string): TTlsConn; virtual; abstract;
    function  Read (c: TTlsConn; buf: Pointer; len: Integer; var got: Integer): TTlsResult; virtual; abstract;
    function  Write(c: TTlsConn; buf: Pointer; len: Integer; var put: Integer): TTlsResult; virtual; abstract;
    procedure Close(c: TTlsConn); virtual; abstract;
  end;
```

- **Async-aware:** `Read`/`Write` return `tlsWantRead`/`tlsWantWrite` (OpenSSL's
  `WANT_READ`/`WANT_WRITE`, the native stack's equivalent) so the async path maps
  them to `WaitReadable`/`WaitWritable` and yields the coroutine. The blocking
  path loops on `PalPoll`. Same contract serves both transports.
- **Selectable:** a global default backend + per-connection override. Default =
  OpenSSL when its lib loads, else native (or configured).
- `http`'s `isTls` branch routes its send/recv through the active backend; the
  pure build/parse helpers are unchanged.

## Backends

- **`tls_openssl.pas`** — thin binding over `libssl`/`libcrypto` via the dynlib
  loader ([[feature-real-dynlib-loader]]). `SSL_CTX_new`/`SSL_new`/`SSL_set_fd`/
  `SSL_connect`/`SSL_read`/`SSL_write`, non-blocking + `SSL_get_error` →
  WANT_READ/WRITE. This makes the dynlib loader a concrete, motivated consumer.
- **`tls_native.pas`** — wraps [[feature-tls13-from-scratch]] behind the same
  vtable. kTLS offload sits under it (per-platform), invisible to callers.

## Testing (the payoff)

- Backend conformance: each backend does a real handshake to a known endpoint.
- **Cross/interop matrix** under `make lib-test` (loopback, coroutine-driven):
  | client \ server | OpenSSL | native |
  |---|---|---|
  | OpenSSL | sanity | native-server correctness |
  | native  | native-client correctness | pure-PXX e2e |
  Each cell: handshake + a GET round-trip. The off-diagonal cells are the interop
  proof (our stack ⇄ OpenSSL).

## Done when

`http` does `https://` through the seam with **either** backend selected; an app
can run one library on OpenSSL and another on native in the same process; the
4-cell client×server interop matrix passes in `make lib-test`. OpenSSL backend is
the default; native is selectable. Security caveat for the native stack stays
documented ([[feature-tls13-from-scratch]]).
