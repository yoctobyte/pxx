---
prio: 53  # auto
blocked-by: [feature-tls13-from-scratch]
---

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

## Slice 6 landed — server side (`SSL_accept`) + OpenSSL⇄OpenSSL interop (2026-06-25)

The OpenSSL backend now plays **both roles** on one active backend. `Handshake`
branches on `role`: clients `SSL_connect`, servers `SSL_accept` (shared
`SslStepHandshake`, want-read/write handling identical so the async resume loop
serves both). `OpenSslTlsServerInit(certFile, keyFile)` builds a server `SSL_CTX`
(`TLS_server_method` + `SSL_CTX_use_certificate_file`/`use_PrivateKey_file`)
alongside the client ctx — a single process can serve and consume TLS at once.

**Verified** (`devtest_tls_interop`, run by `tls-openssl-devtest`): our
OpenSSL-backed HTTPS **server** (accept + seam handshake + `TlsRead`/`TlsWrite`)
⇄ our `HttpGetAsync` **client**, both coroutines on one reactor thread, client
verifying the server cert + hostname → status 200, body intact. So the
client×server interop holds for the OpenSSL backend on both ends (the diagonal +
the our-client⇄s_server cell from slice 3/5).

**Remaining for the umbrella ticket:** the native backend
([[feature-tls13-from-scratch]], deferred) — needed for the off-diagonal
native⇄OpenSSL interop cells. The OpenSSL half of this ticket is functionally
complete (client + server, blocking + async, verified).

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

## Track B sweep (2026-07-20)

The OpenSSL half is functionally complete through slice 6. The **only** remaining
umbrella item is the native backend, and that is
[[feature-tls13-from-scratch]]'s deliverable — which the user deferred
("start alongside BSD support, not now") and which has now been moved to
`rainy-day/` to match. So a `blocked-by` edge, not available Track B work: this
ticket cannot close until that one is un-deferred.

Nothing stops someone pulling a single named slice out of the deferred ticket if
it becomes urgent (RSA-PSS scheme dispatch, kTLS RX). That does not require
un-deferring the umbrella, and it does not change this ticket's state.

Cross-reference to avoid confusion: slice 5 above ("certificate verification +
trust store") is the **OpenSSL** backend's trust, via
`SSL_CTX_load_verify_locations`. The separate `lib/rtl/truststore.pas` landed
2026-07-20 under [[feature-tls-system-trust-store]] anchors the **from-scratch**
client's chain against `/etc/ssl/certs`. Two different backends, two different
trust paths; neither supersedes the other.


## 2026-08-01 (Track B) — measured: the NATIVE backend is the only thing missing

Slice 1 (the seam) shipped. Slice 2, the OpenSSL backend, ships as
`lib/rtl/tls_openssl.pas` and registers itself. **The native backend does not
exist as a unit at all** — `grep TlsRegisterBackend lib/` finds only
`tls_openssl.pas` and the two tests.

So the from-scratch TLS 1.3 client, which now does a real
server-authenticated handshake against ed25519, RSA and ECDSA-P256 servers
([[feature-tls13-from-scratch]]), **cannot be reached from library code**. Its
handshake logic lives in `test/devtest_tls13_handshake.pas`, a devtest program.
Today an `https://` caller's only option is the OpenSSL backend, which needs
`dlopen` + libssl — and that path is itself blocked on two Track A crashes
(see [[feature-real-dynlib-loader]]). The libc-free client that works is the one
you cannot call.

That is the gap between "the handshake works" and "TLS is usable", and it is
this ticket's slice, not the from-scratch ticket's.

### What the extraction involves (for whoever takes it)

Not a wiring job — roughly 300 lines of handshake driving move out of the
devtest into a `tls13_native.pas` implementing `TTlsBackend`:

- `Handshake(fd, role, host, var c)` — currently a straight-line script over a
  connected socket; becomes a state machine, or at minimum a blocking call that
  returns `tlsError` rather than calling `Fail()` and halting.
- `Read`/`Write` — over `tls13_record`, with the kTLS-TX path chosen as it is
  today, and the seam's `tlsWantRead`/`tlsWantWrite` semantics respected so the
  async reactor can drive it.
- `Close`, and registration in `initialization`.

Two properties must survive the move, and both are the kind a refactor drops:

1. **The fail-closed CertificateVerify dispatch.** It rejects any scheme it
   cannot verify. Until 2026-08-01 that path silently ACCEPTED three of the four
   schemes we advertise; do not let it regress to a warning.
2. **Chain verification against the trust store**, not just against a CA handed
   in as a parameter ([[feature-tls-system-trust-store]] is done and has its own
   devtest).

`tools/tls13_handshake_devtest.sh` should keep passing UNCHANGED across the
extraction — it is the proof that nothing was lost, so it is worth leaving it
driving the devtest program rather than rewriting it onto the new API in the
same pass.

## Slice 2 landed — the NATIVE backend (2026-08-01, Track B)

`lib/rtl/tls13_native.pas` implements `TTlsBackend` over the from-scratch TLS
1.3 stack and registers itself. The from-scratch client is now reachable from
library code: `TlsHandshake` / `TlsWrite` / `TlsRead` / `TlsClose` work with no
libssl and no `dlopen`.

### What moved, and what got better on the way

The handshake came out of `test/devtest_tls13_handshake.pas` largely as-is, but
three things are deliberately NOT a straight copy, because the devtest's
versions were fine for a loopback test and wrong for a real client:

1. **Key material is from the OS CSPRNG.** The devtest used FIXED bytes — the
   private key was `Chr(1)..Chr(32)` and the client random `Chr(101)..Chr(132)`.
   Reproducible is the right call for a test and a catastrophe in a client: a
   predictable ephemeral key hands the session to anyone who guesses it. Now
   `OSEntropyBytes` (getrandom(2)), and **failure to get entropy is fatal**
   rather than falling back to a PRNG.
2. **The chain is anchored in the system trust store**, via
   `truststore.VerifyServerChain`, instead of against a single CA handed in as
   `ParamStr(2)`. That also means the whole `certificate_list` is collected and
   walked — the devtest parsed only the leaf — so intermediates work, in any
   order.
3. **`now` comes from the clock**, not from argv.

Errors return `tlsError` and set `Tls13NativeLastError`; nothing calls `Halt`.
The seam reports one failure value and a TLS failure has many distinct causes,
so "it didn't work" is not a diagnosis.

### Limits, stated rather than left to be discovered

- **The handshake is blocking**, and `HandshakeResume` is a no-op. The seam
  explicitly permits this ("a backend over a blocking fd simply returns
  tlsOk/tlsError and never wants"). Driving it from the async reactor needs a
  real state machine — a separate slice. Faking want-read/want-write would be a
  lie the reactor would trip over.
- Client role only; `tlsServer` returns `tlsError`.
- X25519 + AES-128-GCM / ChaCha20-Poly1305, matching what `BuildClientHello`
  offers. No HelloRetryRequest, no resumption.
- kTLS TX offload when available (AES-GCM only); RX always uses the Pascal
  record layer.

### Also landed: `SSL_CERT_FILE`

`LoadSystemTrust` now honours `SSL_CERT_FILE` before the system bundles — the
convention OpenSSL and curl already use, and the way a caller points at a
private CA. **Set-but-unreadable is a hard failure, not a fallback**: someone
who named a trust file meant it, and quietly trusting a different set of roots
than the one they asked for is exactly the surprise a trust store must not
spring. It is also what makes the backend testable without weakening the
default.

### Proven

`tools/tls_native_seam_devtest.sh` (`make tls-native-seam-devtest`), driving a
client that names no `tls13_*` unit beyond the `uses` that registers the
backend:

- **3 accepted** — RSA (rsa_pss_rsae_sha256), ed25519 and ECDSA-P256 servers,
  each a full HTTPS GET returning `HTTP/1.0 200`.
- **4 refused** — untrusted root, hostname mismatch, empty trust file, missing
  trust file. These carry as much weight as the positives: a client that
  accepts everything passes every positive test.

Both existing devtests pass **unchanged**, which is the evidence the extraction
lost nothing: `tls13-handshake-devtest` (ed25519 + rsa_pss + ecdsa_p256, kTLS-TX
and Pascal fallback) and `truststore-devtest` (10 assertions, still green after
the `SSL_CERT_FILE` change).

### Registration is EXPLICIT (corrected after review)

The first cut registered the backend from `tls13_native`'s `initialization`.
That was wrong and was caught by comparing against the only other backend:
`tls_openssl` registers only when `OpenSslTlsRegisterEx` is called. Merely
LINKING a unit must not change which TLS stack a program trusts — that is a
process-global, and deciding it by link order is exactly the kind of thing that
is invisible until it bites.

So `Tls13NativeRegister` is an explicit call and the initialization section
registers nothing. That also happens to be the mechanism the "which backend
when both are present" question needs: calling one registrar after the other is
a deterministic override rather than a race between two initialization
sections. The seam devtest asserts `not TlsAvailable` before it registers, so
the absence of the side effect is tested rather than assumed.

### What this unblocks

`https://` over the native stack no longer needs [[feature-real-dynlib-loader]],
which is blocked on two Track A crashes. The remaining work to make it the
default for `http.pas` is choosing a backend when both are registered — not
covered here.

### End to end: `HttpGet` over `https://` with no OpenSSL in the process

`http.pas` already routed https through the seam and already treated the
handshake as completing within one `TlsHandshake` call — which is exactly what
this backend does — so nothing there needed changing. Verified rather than
assumed:

```
backend=native-tls13
status=200 reason=ok
HTTPS OK
```

Asserted in the seam devtest as `HttpGet over https (no libssl in the
process)`, driven by `test/devtest_https_native.pas`, which names no TLS unit
beyond the registrar.

Two stale claims in `http.pas`'s header fixed while there: it said "no backend
ships in-tree yet" (two do now, and it now names both registrars and what each
costs), and that only "the mock and a blocking OpenSSL backend" complete the
handshake in one call.

### Slice 3 is the ASYNC handshake — user-prioritised (2026-08-01)

Rene, asked which of the remaining TLS items matters: **"async is a primary
feature."** So this is not a nice-to-have behind interop breadth — it is the
next slice, and it is pre-approved: a fresh session should start it without
re-asking for scope.

Today `Handshake` is blocking and `HandshakeResume` is a no-op. The seam permits
that and `http.pas` is happy with it, but the coroutine reactor cannot drive it,
so every https request occupies a thread for the length of a handshake. Making
it real means a state machine over the flight parser — the loop that currently
blocks in `ReadRecord` becomes a resumable step returning `tlsWantRead` — and
`HandshakeResume` picking up where it left off.

Do NOT fake it: returning a want the backend cannot honour is worse than
blocking, because the reactor will believe it. The two properties in the header
above (fail-closed CertificateVerify, trust-store anchoring) must survive the
rewrite, and `tls13-handshake-devtest` + `truststore-devtest` must keep passing
unchanged as the evidence they did.
