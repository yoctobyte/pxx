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

**Next slices:** (a) route `http`'s `isTls` branch through the seam (`https://`
does TlsHandshake-after-connect, send/recv via Tls*; clean error when
`not TlsAvailable`) + a mock-backed `https` e2e; (b) the OpenSSL backend
([[feature-real-dynlib-loader]]); (c) the native backend
([[feature-tls13-from-scratch]], deferred).

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
