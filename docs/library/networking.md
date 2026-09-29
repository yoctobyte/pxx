---
title: Networking (HTTP / HTTPS)
order: 51
---

# Networking — the `http` unit

PXX ships its own native HTTP/1.1 client (not a wrapper around an external
library). It does URL parsing, request building, response framing
(`Content-Length` and chunked `Transfer-Encoding`), redirects, keep-alive,
connection pooling, and — with a TLS backend registered — `https://`.

```pascal
program get_example;
uses http;
var r: THttpResponse;
begin
  r := HttpGet('http://example.com/');
  if r.Ok then
  begin
    writeln('status ', r.Status, ' ', r.Reason);
    writeln('content-type: ', HttpResponseHeader(r, 'Content-Type'));
    writeln(Length(r.Body), ' bytes');
  end
  else
    writeln('request failed');
end.
```

The plain `http://` client needs no libc, and it runs on every Linux target:
on 2026-09-28 the program above printed `status 200 OK`, the content type and
the body length against example.com, built for x86-64, i386, aarch64, arm32 and
riscv32 with pin v446 (compiler sha256 `ae3466a018d8`) and with the compiler at
`e072d579b0`, the cross targets under QEMU user mode.

## The response record

```pascal
type
  THttpResponse = record
    Ok:      Boolean;      // transport + parse succeeded
    Status:  Integer;      // e.g. 200; 0 if unparsed
    Reason:  AnsiString;   // e.g. 'OK'
    Headers: AnsiString;   // raw header block (no status line)
    Body:    AnsiString;
  end;
```

Read a single header without parsing the whole block, or get them structured:

```pascal
ct   := HttpResponseHeader(r, 'Content-Type');   // case-insensitive, '' if absent
hdrs := HttpResponseHeaders(r);                  // THttpHeaders: name/value pairs
```

## Methods and helpers

| Call | Does |
| --- | --- |
| `HttpGet(url)` | GET |
| `HttpPost(url, contentType, body)` | POST with a body |
| `HttpHead` / `HttpPut` / `HttpDelete` | the matching method |
| `HttpExec(method, url, extraHeaders, body)` | any method + custom headers |
| `HttpGetFollow(url, maxRedirects)` | follow up to N `3xx` `Location` hops |
| `HttpUrlEncode` / `HttpUrlDecode` / `HttpQueryAdd` | query / form encoding |

Each call returns a `THttpResponse`. `extraHeaders`, when non-empty, is
CRLF-terminated lines; a `Content-Length` is added automatically when a body is
present.

## Async (reactor) variants

Every call has an `…Async` form (`HttpGetAsync`, `HttpExecAsync`, …) that runs on
the coroutine reactor (`scheduler`): call it from inside a coroutine and it yields
instead of blocking, so one thread can drive many requests (and servers)
concurrently. Keep-alive (`THttpConnection`) and a connection pool
(`HttpGetPooledAsync`) reuse sockets across requests.

## HTTPS

`https://` URLs are routed through a pluggable **TLS seam** (`tls` unit). The
`http` unit itself contains no crypto; it asks whichever TLS backend is
registered to handshake and to encrypt/decrypt the bytes. If **no** backend is
registered, an `https://` request fails cleanly (`Ok` is `False`) — it never
crashes.

### OpenSSL backend

The `tls_openssl` unit provides a backend that loads the system `libssl` at
runtime (via `dlopen`). Because loading a shared library pulls in libc, it is
**opt-in**: build with `-dPXX_DYNLIB_LIBC` (the default build stays libc-free and
has no dynamic loader). Register it once at startup, then use the normal `http`
calls. `OpenSslTlsRegister` is **secure by default** — it verifies the peer
certificate against the system trust store and checks that the certificate
matches the hostname; an untrusted or mismatched certificate fails the request
(`Ok` is `False`).

```pascal
program https_example;
uses http, tls_openssl;
var r: THttpResponse;
begin
  if not OpenSslTlsRegister then   // dlopen libssl + register as the TLS backend
  begin
    writeln('no TLS backend (build with -dPXX_DYNLIB_LIBC, and libssl present)');
    Halt(1);
  end;
  r := HttpGet('https://example.com/');
  writeln('status ', r.Status);
end.
```

Build and run:

```sh
pxx -dPXX_DYNLIB_LIBC -Fulib/rtl/platform/posix https_example.pas https_example
./https_example
```

Both the blocking (`HttpGet`/`HttpExec`) and async (`HttpGetAsync`, …) families
work over HTTPS: the async handshake yields on the reactor while OpenSSL waits for
the socket, so TLS requests compose with everything else on the coroutine loop.

### Trust store and private CAs

To trust a private or self-signed CA (e.g. an internal service, or a test
server), register with `OpenSslTlsRegisterEx(verifyPeer, caFile)`:

```pascal
OpenSslTlsRegisterEx(True, '/path/to/ca.pem');   // system store + this CA, verified
```

`caFile` is added on top of the system trust store. From pin v448 a `caFile`
that cannot be loaded (missing, or not a certificate) makes it return
`False`: check the result. With v447 and earlier,
`OpenSslTlsRegisterEx(True, '/nonexistent/ca.pem')` returns `True` and only
the system store is used (measured 2026-09-28 on x86-64 and i386; the fix is
`9df5de0690`). Passing `verifyPeer = False`
turns verification off entirely — only for development against throwaway
endpoints; never in production. After a refused handshake,
`OpenSslTlsLastVerifyResult` returns the OpenSSL `X509_V_*` code explaining why.

### Server-side TLS

The backend can also play the server role. `OpenSslTlsServerInit(certFile,
keyFile)` builds a server context from a PEM certificate + key; an accepting
socket then handshakes with `TlsHandshake(fd, tlsServer, '', conn)` (driving
`TlsHandshakeResume` on want-read/write, the same loop the client uses) and moves
bytes with `TlsRead` / `TlsWrite`. Client and server share the one backend, so a
single process can both serve TLS and make TLS requests. (There is no high-level
HTTPS *server* object yet — you wire `accept` + the seam yourself; the `http`
unit itself is a client.)

**Current limits of the OpenSSL backend:** x86-64, and i386 from v448.
On x86-64 the examples on this page ran against example.com, and a
self-signed certificate and a certificate for the wrong host were both
refused (`OpenSslTlsLastVerifyResult` 18 and 62). Measured on 2026-09-28 with
v446 and with the compiler at `e072d579b0`, the other targets under QEMU user
mode:

- i386: `OpenSslTlsRegister` crashes the program (segmentation fault) with
  v446 and v447. From v448 (`9df5de0690`) it works: with pin v448
  (`b2b325036c3b`) under QEMU on 2026-09-28, the HTTPS example above printed
  `status 200` (v447: segmentation fault). Earlier, with pin v447 and the
  fixed library at `2f79422e6a`, both bad certificates were refused, as on
  x86-64.
- aarch64 and arm32: `OpenSslTlsRegister` returns `False` (checked under QEMU,
  without a libssl for those targets installed).
- riscv32: refused at compile time, because it has no dynamic loader.

### Native backend

A from-scratch TLS 1.3 client, `tls13_native`, sits behind the same seam
and needs no C library: call `Tls13NativeRegister` instead of
`OpenSslTlsRegister`, and `Tls13NativeLastError` says why a handshake
failed. It checks the server's certificate chain against the system trust
store. With v451 it cannot check a certificate signed with ECDSA and
SHA-384, which most public sites use somewhere in their chain, so most
`https://` requests through it fail. In a measurement of seven well-known
sites, only www.python.org worked. See
[Known issues](../reference/known-issues.md#native-tls-most-https-sites-fail-certificate-verification)
for the list, and use the OpenSSL backend where you can.
