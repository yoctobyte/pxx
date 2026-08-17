---
track: A
prio: 50
type: bug
blocked-by: []
summary: "A Synapse TLS client handshake segfaults inside libcrypto's X509_verify_cert with RIP pointing INTO THE STACK (rax == rip — a tail call through a function pointer holding a stack address). The byte-identical program built with FPC completes the handshake. The loader, the dlsym'd symbols and C->Pascal callbacks are each separately proven working, so the fault is ours and is narrower than any of them."
status: done
owner: frank2
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

## 2026-08-17 (frank2, Track A) — RESOLVED. `@procvar` means something different in delphi mode.

Re-measured at HEAD first: **both premises still hold.** pxx segfaults, FPC
prints `ssl=0`, same machine / OpenSSL 3.0.13 / server. Track B's five negatives
were inherited and none of them needed re-treading — the cause is narrower than
all of them, exactly as they said.

### Root cause

`ssl_openssl3_lib.pas:832` forwards the verify callback as

```pascal
procedure SslCtxSetVerify(ctx: PSSL_CTX; mode: Integer; arg2: PFunction);
begin
  if InitSSLInterface and Assigned(_SslCtxSetVerify) then
    _SslCtxSetVerify(ctx, mode, @arg2);      // <-- @ over a VALUE PARAMETER
end;
```

`PFunction = procedure` — a procedural type — and **`@` over a procedural
variable is mode-dependent in FPC.** Measured, not recalled, with a probe of
this exact shape:

| mode | `@arg2` |
| --- | --- |
| delphi / tp | the code pointer `arg2` **holds** (`0` for nil) |
| objfpc / fpc | the **address of the variable** (a stack slot) |

PXX did the objfpc thing unconditionally. So where FPC passes `NULL`, PXX passed
**the address of a live stack parameter**. OpenSSL stored it as the verify
callback, `X509_verify_cert` called it after the server certificate arrived, and
control transferred into the stack.

That accounts for every register in the report: `rip == rax` because it is an
indirect tail call, both inside `[stack]` because the pointer IS a stack
address, and the fault landing in cert verification because that is simply when
the stored pointer is first used — arbitrarily far from the call that set it.

### Fix

One branch in the `@` factor: in `DelphiMode`, `@sym` where `SymProcSig[sym] >= 0`
yields the lvalue rather than `AN_ADDR` over it. Scoped to `DelphiMode`, so PXX's
own objfpc-ish dialect and the compiler's own sources are untouched — confirmed
by the objfpc half of the test being byte-identical before and after, and by the
self-host fixedpoint.

`-Mtp` deliberately NOT keyed on: FPC's tp agrees with delphi here, but PXX
accepts `-Mtp` as inert by existing policy (the mode-switch test asserts it).
Changing that is a separate decision, not a rider on this fix.

### Verified

- **the ticket's gate**: `sslprobe` prints `connect=0` / `ssl=0` under pxx,
  matching FPC on the same machine and server;
- `test/test_pascal_at_procvar_mode.pas`, enumerated in `make test` under BOTH
  `-Mdelphi` and `-Mobjfpc`. The two runs must differ, so it cannot pass if the
  mode is ignored. **2x2 differential against FPC 3.2.2: all four cells agree.**
- confirmed RED on a baseline built from HEAD-minus-this-diff (delphi mode
  produced the objfpc row), so the test is real and the scoping is proven.

### FOLLOW-UP `e6f2264d3` — the first fix was in the wrong PLACE, and a node-kind coupling is why

`2ee660831` put the change in the parser's `@` factor, rebuilding `@fp` as an
`AN_IDENT` carrying the procvar's value. That went NEW-RED in
`test_procvar_value_context` (line 116, delphi: `Int64(@fpNil) = 0`).

**The coupling that caused it, named here because it is invisible at the edit
site.** `IRProcVarAutoCall` (`ir.inc`) implements the OTHER delphi rule — a bare
procvar in a value context is CALLED — and it exempts `@fp` **by node kind**:

```pascal
if (n < 0) or (ASTKind[n] <> AN_IDENT) then Exit;   { `@fp` is AN_ADDR, ... }
```

So the exemption is a property of what the parser happens to BUILD, with nothing
referencing it from the parser side. Any change that rebuilds that expression as
a different node silently acquires the auto-call, nothing fails where the edit
was made, and the damage surfaces as unrelated behaviour — here, `@fp` quietly
becoming `fp()`.

**Resolution:** keep the node `AN_ADDR`, so every existing exemption still
applies by construction, and change only what it LOWERS to — in `AN_ADDR`'s
lowering, beside the `@s`-on-a-managed-string special case, which is the same
shape. Adding a condition to the guard would have worked and is worse: it grows
the special case instead of leaving one path.

### The assertion that looked like coverage and was not

Line 116 asserts `Int64(@fpNil) <> 0` where `fpNil` holds `@ImplNil`. **That is
true under BOTH address-of and value-of** — it separates only the third answer
(the call result, 0). It had been green on `pinned` for the wrong reason, and it
is why the original mode measurement and the test could both be honest and
disagree.

Rule earned: **ask of any assertion which OTHER candidate answers would also
satisfy it.** N candidate behaviours need a discriminator with N distinguishable
outputs. Getting one here meant obtaining the variable's own address through a
route that is not `@` at all — an untyped `var` parameter — which is the same
"the evidence must sit outside the thing being varied" rule as the count
assertion and the self-overwriting differential below.

`test_pascal_at_procvar_mode` shared that blind spot (it only tested a
PARAMETER, where the two readings collapse) and now carries the three-way
VARIABLE case: 5 assertions x 2 modes, all ten cells matching FPC 3.2.2, RED on
the pre-fix baseline.

### Two traps worth recording

**A stale binary nearly sent me the wrong way.** Building the FPC control as
`sslprobe` overwrote the pxx binary of the same name, and the next three
LD_PRELOAD experiments "proved" that preloading libcrypto fixed the crash. It
did not — I was running the FPC build. Distinct output names (`_pxx` / `_fpc`)
from the start, or the differential lies to you and reads as a discovery.

**A brace comment does not nest, so `{$MODE DELPHI}` inside one is ARMED.** The
first draft of the test documented the mode table using directive spelling; FPC
parsed it as a real directive and refused the file. Mode names are written bare
in the test for this reason, with a note saying why.

## Gate

`sslprobe` above completes the handshake and prints `ssl=0` under pxx, matching
FPC. Then item (d) of `feature-real-dynlib-loader` can add a real end-to-end TLS
assertion to `lib-test`.

## Log
- 2026-08-17 — resolved, commit 2ee660831.
