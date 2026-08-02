---
track: P
prio: 80
type: bug
---

# A procedural variable in a value context takes its ADDRESS instead of calling it

- **Type:** bug (Pascal frontend semantics, silent wrong value) — **Track P**
- **Found:** 2026-08-02 by the Track B agent, narrowing the Synapse/OpenSSL
  crash left open on [[feature-real-dynlib-loader]] item (d). Filed, not fixed:
  the Pascal frontend lives in the shared `lexer.inc`/`parser.inc`, which is not
  Track B's to edit.

## Minimal repro

```pascal
program pv;
{$MODE DELPHI}
type TF = function: Pointer; cdecl;
var fp: TF; magic: Pointer;

function Impl: Pointer; cdecl;
begin Impl := magic; end;

function ViaBareName: Pointer;
begin
  if Assigned(fp) then Result := fp else Result := nil;
end;

begin
  magic := Pointer(Int64($DEADBEEF));
  fp := @Impl;
  writeln(Int64(ViaBareName));
end.
```

| | `Result := fp` yields |
| --- | --- |
| **FPC 3.2.2, `{$MODE DELPHI}`** | `3735928559` — the value `fp()` returns (**called**) |
| **pxx `--mimic-fpc`** | `4198544` — `@Impl` (**address taken, never called**) |

A procedural variable named in a context that wants a VALUE must be called.
Taking its address is what `@fp` is for. Note `fp()` with explicit parens is
already correct in pxx — only the bare-name form is wrong, so the two spellings
disagree, and the wrong one is the one real Delphi code uses.

Verified against FPC in `{$MODE DELPHI}` specifically because that is the mode
the affected unit declares; the oracle was run, not remembered.

## Why this is bad rather than obscure

The wrong result is a **valid pointer**, so nothing errors. It is assigned,
returned, and passed onward, and the program dies far away — the exact
plausible-wrong-value shape `devdocs/dev/debugging-playbook.md` describes. And
the idiom is not exotic: "load a function pointer at runtime, wrap it in a
function that calls it" is how every dynamic-binding layer in Delphi-family
code is written, so this affects any such library, not just the one below.

Related but distinct: [[frank2-paramless-name-semantics]] covers a FUNCTION's
own name inside its body (bare name = result variable). This is a procedural
VARIABLE in an expression, which is a different rule with the opposite answer.

## The chain it was found through, end to end

Synapse `external/synapse/ssl_openssl3_lib.pas:613`:

```pascal
function SslMethodTLS: PSSL_METHOD;
begin
  if InitSSLInterface and Assigned(_SslMethodTLS) then
    Result := _SslMethodTLS        { <- procvar in a value context }
```

1. FPC calls it and returns OpenSSL's `SSL_METHOD*`. pxx returns
   `@TLS_method` — the address of the loader-resolved function itself.
2. Synapse hands that to `SSL_CTX_new`.
3. libssl dereferences it as a method table and dies:
   `call *0xb8(%r12)` with `rdi`/`rsi` `0`.

Confirmed by simulation rather than inference — driving OpenSSL 3 directly
through our own `dlopen`:

```
SSL_CTX_new(TLS_client_method())   -> ctx non-nil, fine
SSL_CTX_new(@TLS_client_method)    -> SEGFAULT
```

## What this clears

The 2026-07-31 note on [[feature-real-dynlib-loader]] guessed this crash was "a
marshalling or symbol-resolution fault on the indirect-call path, i.e. Track A
again". **That is ruled out.** Driving OpenSSL 3 directly through our `dlopen`
works completely: `OPENSSL_init_ssl` returns 1, `TLS_method` and
`TLS_client_method` resolve, and `TLS_client_method()` / `SSL_CTX_new()` /
`SSL_new()` all return non-null. Our loader, our `dlsym`, and our cdecl
indirect-call marshalling are all fine against the same library. The fault is
this frontend semantics bug alone.

## Gate

The repro above returns FPC's value; `fp` and `fp()` agree; `@fp` still yields
the address. Then Synapse's `SSLDoConnect` reaching a real TLS handshake, which
is [[feature-real-dynlib-loader]] item (d) and is the end-to-end check.
