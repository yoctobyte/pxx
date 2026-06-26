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

`caFile` is added on top of the system trust store. Passing `verifyPeer = False`
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

**Current limits of the OpenSSL backend:** x86-64 only (where the dynamic loader
is verified).

A from-scratch native TLS stack is planned as a second, interchangeable backend
behind the same seam.
