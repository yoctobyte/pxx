---
track: A
prio: 50
type: bug
blocked-by: []
summary: "A Synapse TLS client handshake segfaults inside libcrypto's X509_verify_cert with RIP pointing INTO THE STACK (rax == rip — a tail call through a function pointer holding a stack address). The byte-identical program built with FPC completes the handshake. The loader, the dlsym'd symbols and C->Pascal callbacks are each separately proven working, so the fault is ours and is narrower than any of them."
---

# A Synapse TLS handshake jumps into the stack inside `X509_verify_cert`

- **Type:** bug (wrong pointer handed to a C library → control transfer to data)
  — **Track A**. Found from Track B, which cannot fix it.
- **Found:** 2026-08-17 by frank3, working item (d) of
  [[feature-real-dynlib-loader]] with the debugger that
  `bug-a-dwarf-emission-recurses-forever-on-mutually-referencing-classes`
  unblocked.
- **Measured against:** `pinned` **v344**, x86-64, OpenSSL 3.0.13,
  `-dPXX_DYNLIB_LIBC`. Not re-checked at HEAD.

## Repro

Server: `openssl s_server -quiet -accept 44330 -cert cert.pem -key key.pem`
(self-signed, `CN=localhost`).

```pascal
program sslprobe;
{$MODE DELPHI}
uses synautil, blcksock, ssl_openssl3;
var s: TTCPBlockSocket;
begin
  s := TTCPBlockSocket.Create;
  try
    s.ConnectionTimeout := 3000;
    s.Connect('127.0.0.1', '44330');
    WriteLn('connect=', s.LastError);
    if s.LastError <> 0 then Halt(1);
    s.SSLDoConnect;
    WriteLn('ssl=', s.SSL.LastError, ' ', s.SSL.LastErrorDesc);
  finally
    s.Free;
  end;
end.
```

```
pxx --mimic-fpc -dPXX_DYNLIB_LIBC -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posix
  connect=0
  ssl-class=ssl_openssl3
  Segmentation fault
```

## The oracle disagrees — so this is ours

**The byte-identical source built with FPC completes the handshake:**

```
fpc -Mdelphi -Fuexternal/synapse
  connect=0
  ssl-class=ssl_openssl3
  ssl=0            <-- handshake OK
```

Same machine, same OpenSSL, same server, same `.pas` file.

## What the fault actually is

```
Program received signal SIGSEGV
0x00007fffffffd7d8 in ?? ()
rip 0x7fffffffd7d8   rax 0x7fffffffd7d8   rsp 0x7fffffffd6a8   rdi 0x0
[rsp] = 0x7fffe7983238
```

**`rip == rax`, and `rip` is inside `[stack]`** (`0x7ffffffdd000-0x7ffffffff000`).
`[rsp]` holds a return address pointing just past a *direct* call, which means
the transfer was a **tail call** — the callee restored its frame and did
`jmp *%rax` — through a function pointer whose value is a stack address.

Symbols resolved by hand, since gdb sees none (the libraries are `dlopen`ed and
its probes-based linker interface fails): each address minus its mapping base,
then the nearest preceding dynamic symbol.

| frame | resolves to |
| --- | --- |
| caller of the crash | `X509_get_pubkey_parameters +0x193` (libcrypto) |
| its call target | `X509_cmp_time +0x4d0` (libcrypto) |
| deeper | `OPENSSL_sk_insert +0x35` |
| deeper | **`X509_verify_cert +0xc7`** |
| deeper | `SSL_get_ex_data_X509_STORE_CTX_idx +0xe40` (libssl) |

These are nearest-preceding *exported* symbols, so the real functions are
libcrypto statics inside the certificate-verification path. The failure is
therefore during **chain verification of the server certificate**, in a callback
or method-table slot that should hold code and holds a stack address instead.

## What is NOT wrong — measured, so nobody re-treads it

Each of these was an obvious suspect; each is exonerated by its own test.

1. **The dlopen loader.** `InitSSLInterface` returns True and
   `OpenSSLVersion(0)` answers `OpenSSL 3.0.13 30 Jan 2024` — real symbols out
   of a real `.so`. Now gated as `test/lib_synapse_ssl.pas` in `make lib-test`.
2. **C→Pascal callbacks through a `dlsym`'d pointer.** A `cdecl` Pascal
   comparator handed to libc's `qsort` via `GetProcedureAddress` sorts correctly
   (`1 3 5 7 9`), and `@CmpInt` is a code address, not a stack one.
3. **`ssl_openssl3_lib.pas` compiling.** It does, after the `HModule` fix in
   `lib/rtl/sysutils.pas` (Track B, landed with this ticket).
4. **The connect path.** `connect=0`; the errno bug that used to stop it here
   (`bug-b-sockets-fp-wrappers-return-raw-negative-errno-and-fpgeterrno-is-a-constant`)
   is fixed.
5. **Synapse's own callback surface.** The unit installs exactly one callback,
   `SslCtxSetDefaultPasswdCb(FCtx, @PasswordCallback)`, which is not on the
   verify path. The `X509_STORE_add_cert` loop that would populate a store sits
   inside the **PFX** branch and does not execute for this probe.

So it is not the loader, not callbacks in general, not the socket layer, and not
a missing binding. It is narrower than all of them.

## Suggested next step — deliberately not guessed at here

What wants identifying is which OpenSSL entry point *receives* the bad value,
not which one crashes. The probe is three lines and reproduces on every run, and
`-g` now works on a `TTCPBlockSocket` program, so a breakpoint on Synapse's SSL
connect plus a watch on the `SSL_CTX`/`SSL` pointers it passes should name it
directly.

Track B stopped here rather than theorise. The last two times this ticket family
guessed at a cause instead of measuring one the guess was wrong — see
`feature-real-dynlib-loader`'s 2026-08-02 note (the "marshalling or symbol
resolution" guess, actually a procvar-in-value-context bug) and its 2026-08-15
note (the "inside libssl" guess, actually our own errno).

## Gate

`sslprobe` above completes the handshake and prints `ssl=0` under pxx, matching
FPC. Then item (d) of `feature-real-dynlib-loader` can add a real end-to-end TLS
assertion to `lib-test`.
