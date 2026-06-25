---
title: Networking (HTTP / HTTPS)
order: 31
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
calls:

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

**Current limits of the OpenSSL backend (x86-64):**

- **No certificate verification yet.** The connection is encrypted, but the peer
  certificate is not validated against a trust store. Treat the current TLS
  support as suitable for development and trusted/loopback endpoints, not as
  protection against an active attacker. Verification is planned.
- **Client only.** Server-side TLS (`SSL_accept`) is not wired yet.

A from-scratch native TLS stack is planned as a second, interchangeable backend
behind the same seam.
