---
track: B
prio: 45  # auto
type: feature
blocked-by: [bug-a-synapse-tls-handshake-jumps-into-the-stack-inside-x509-verify-cert]
summary: "Real dlopen loader: DONE on x86-64 (PAL primitives, opt-in -dPXX_DYNLIB_LIBC, truthful PalHasDynlib, OpenSSL 3 loaded and answering). Two items open: (b) an arm32/aarch64 RUN, blocked on this host having no cross ld-linux/libc, and (d) Synapse SSL end-to-end, now past the connect wall and stopped in SSLDoConnect."
---

# Real dynamic-library loader (`dlopen`) — PAL primitives + libc policy

- **Type:** feature / design decision (runtime infrastructure)
- **Status:** working
- **Owner:** frank3
  the link-libc profile / loader-vs-link decision)
- **Opened:** 2026-06-24
- **Found-by:** Synapse recon ([[feature-synapse-compile-check]]) — `dynlibs`
  stub unblocks compile but cannot actually load anything (SSL/TLS).
- **Relation:** consumed by [[feature-synapse-compile-check]] (only for the
  SSL/TLS path; the plain-HTTP path needs only the stub). Also the concrete
  prerequisite for the **OpenSSL backend** of
  [[feature-tls-provider-abstraction]] (dlopen `libssl`/`libcrypto`). Relevant to
  many future projects, not just Synapse.

## Context

`dynlibs` ships now as an **honest stub** (`LoadLibrary -> NilHandle`,
`GetProcAddress -> nil`); that is correct for libc-free POSIX, which has no
runtime loader. This ticket tracks giving PXX a *real* loader when a project
genuinely needs one (first consumer: Synapse SSL/TLS via `LoadLibrary('libssl')`).

Today there is a latent inconsistency: `PalBackendHasDynlib` returns **True** on
posix (`lib/rtl/platform/posix/platform_backend.pas:181`) but **no
`PalDlOpen`/`PalDlSym`/`PalDlClose` primitives exist**. Until a real loader
lands, `PalHasDynlib` is lying. Interim: either (a) flip it to **False** so
callers correctly see "no loader", or (b) leave True and let `dynlibs` stub
return nil — decide when wiring this.

## Policy (user, 2026-06-24)

Ordered preference:

1. **Syscall-only by default.** Get by with raw syscalls even if it needs
   helpers. Do NOT pull in libc just to have a loader.
2. **Load libc only when the user really wants something from libc** — i.e. a
   real `dlopen` need (loading `.so` files we don't control, like OpenSSL).
3. **"Cheat" and dlopen via libc is acceptable ONLY if it is *much* easier**
   than a from-scratch loader, and only on the opt-in path — never the default.

So this is **opt-in**, like `--mimic-fpc`: a project that wants real dynamic
loading asks for it; the syscall-only core stays clean and libc-free.

## Two implementation routes

- **A. Link libc, wrap `dlopen`/`dlsym`/`dlclose` (the "cheat").** Far less code:
  `PalDlOpen` etc. become thin externs. Cost: the binary now links libc (a glibc
  dependency, dynamic linker startup, the very thing the syscall-only core
  avoids). Gate behind an opt-in **link-libc profile** (Track A: linker/driver
  must emit the libc link + dynamic interp). Good default *for this feature's
  opt-in path*.
- **B. From-scratch ELF `.so` loader over `mmap`/`openat` syscalls.** Keeps the
  libc-free invariant even with dynamic loading: parse the ELF, `mmap` segments,
  apply relocations, resolve symbols. Large, but the "platonic" answer and reusable
  everywhere. Defer unless route A's libc dependency is unacceptable for a target.

Recommendation: **A behind an opt-in link-libc profile** for the first real need;
keep B as the rainy-day ideal.

## Done when

- `PalDlOpen`/`PalDlSym`/`PalDlClose` exist with a real backend on at least the
  posix target, reachable via an **opt-in** profile (never the default build).
- `PalHasDynlib` / `PXX_HAS_DYNLIB` reflect reality (True only when a loader is
  actually present for the active profile).
- `lib/rtl/dynlibs.pas` `LoadLibrary`/`GetProcAddress` route to the real
  primitives under that profile, still returning nil/NilHandle when no loader.
- A smoke test loads a known `.so` (e.g. `libm`/`libssl`), resolves one symbol,
  calls it — under the opt-in profile, in `make lib-test`.
- Syscall-only default build is unchanged: no libc, loader absent, stub behaviour.

## Notes

- Coordinate the libc-link emission with Track A (linker/driver) — that half is
  `compiler/**`, so the link-libc profile likely wants its own Track A ticket
  once route A is chosen.
- Until then `dynlibs` stub is the contract; do not fake `GetProcAddress`.

## Resolution (2026-06-25, Track A — route A, opt-in, x86-64)

Implemented route A (wrap libc dlopen/dlsym/dlclose) per the user's "AMD64 first,
port later" direction. PXX already emits a dynamically-linked ELF for any
`external '<soname>'` routine, so no loader infrastructure was needed — two
compiler fixes (the `external name 'sym'` link-symbol bug via ProcExtName; quiet
the PChar-coercion mismatch diag) plus lib/rtl/dynlibs.pas.

dynlibs.pas: opt-in `-dPXX_DYNLIB_LIBC` -> LoadLibrary/GetProcedureAddress/
UnloadLibrary wrap dlopen(RTLD_NOW)/dlsym/dlclose; default stays the libc-free
stub. Honors the policy (libc-free default, opt-in like --mimic-fpc). Verified:
load libc.so.6, dlsym strlen, call via proc var -> 5. Test: test/test_dynlib.pas.

Remaining (follow-ups, not blocking): (a) factor PalDlOpen/Sym/Close PAL
primitives + reconcile PalBackendHasDynlib; (b) port to other targets (extern +
dynsym emission is already target-indep; needs per-target run verification);
(c) cdecl on PROC TYPES + cdecl indirect calls for strict multi-arg/float C
signatures (current int/ptr proc-var calls match System V on x86-64); (d) Synapse
SSL/TLS end-to-end. Status -> partial/done-for-x86-64; leaving ticket in backlog
for the PAL+multi-target follow-up unless closed.

## Update (2026-06-25): cdecl indirect calls DONE (x86-64)

Follow-up (c) landed (c461fce): `cdecl` on proc TYPES + System V indirect-call
marshalling on x86-64 (int->rdi.., float->xmm0.., 16-byte aligned, float
return). A dlsym'd C function with float args now calls correctly through a
`function(...): R; cdecl` pointer (sqrt/pow/ldexp verified). Remaining: stack
spill (>6 int / >8 float), by-value structs, varargs; and porting the indirect
cdecl path to the other targets. (a) PAL primitives and (d) Synapse SSL still open.

## Update (2026-07-12): follow-up (a) DONE — PAL primitives + truthful capability

`PalDlOpen`/`PalDlSym`/`PalDlClose` factored into the PAL (posix backend: real
dlopen/dlsym/dlclose behind `-dPXX_DYNLIB_LIBC`, honest nil/0 stubs otherwise;
ESP backend: always stubs). `dynlibs.pas` is now a thin FPC-surface over PAL
with no ifdefs or externs of its own. **PalBackendHasDynlib reconciled:** it
was unconditionally True on posix while the default build's loader was a stub —
now it reports whether LoadLibrary actually works (True only with the define),
and `lib_platform`'s expected output dropped its 'dynlib' line accordingly
(the compile-time PXX_HAS_DYNLIB define is unchanged — that gates the surface,
not the runtime loader). test_dynlib green in both modes; make lib-test green.
Remaining: (b) other-target run verification, (d) Synapse SSL end-to-end
(gated on the jedi.inc lexer bug, see bug-pascal-directive-inside-paren-star-comment).

- 2026-07-19 (backlog sweep note) UNBLOCKED: the jedi.inc directive-in-comment lexer bug blocking item (d) Synapse-SSL end-to-end is resolved (in done/). All done-when bullets met on x86-64; remaining = (b) other-target run verification + (d).

- 2026-07-20 (Track B) — Item **(d) Synapse SSL end-to-end is NOT unblocked**
  after all; the 2026-07-19 sweep note is too optimistic. The jedi.inc lexer bug
  it named is indeed fixed, but `external/synapse/ssl_openssl3_lib.pas` now stops
  on a different wall:

  ```
  pascal26:1111: error: cdecl indirect call: more than 6 integer args not supported yet
  ```

  OpenSSL has plenty of 7+ argument entry points and Synapse binds all of them
  through `dlopen` + function pointers, so the unit cannot compile and the
  end-to-end test that would actually exercise the loader cannot be written.
  Filed as [[bug-cdecl-indirect-over-6-integer-args]] (Track A). Note that
  [[feature-cdecl-indirect-cross-targets]], marked done, lists ">6/>4 args
  marshals correctly" in its acceptance — that is not true of the indirect path
  today, and the two should be reconciled.

  Landed on the way: `HModule` in `lib/rtl/dynlibs.pas` as an alias of
  `TLibHandle`. Synapse's loader helpers are declared `function LoadLib(const
  Value: String): HModule`, and that spelling simply did not exist in our
  dynlibs. Source compatibility, not a second type. `lib_synapse` still green.

  So item (d) stays open and is now **blocked on Track A**, not on Track B.
  Item (b) (other-target run verification) is unchanged and needs the cross
  runners.


## 2026-07-31 (Track B) — item (d) is UNBLOCKED and half-done; a new Track A wall behind it

The Track A blocker named in the 2026-07-20 note,
[[bug-cdecl-indirect-over-6-integer-args]], is resolved (in `done/`), and the
consequence was measured rather than assumed:

- **`ssl_openssl3_lib.pas` COMPILES.** The `more than 6 integer args` error is
  gone.
- **OpenSSL loads and answers through our `dlopen`.** `InitSSLInterface` returns
  True and `OpenSSLVersion(0)` prints `OpenSSL 3.0.13 30 Jan 2024` — real
  symbols, resolved at run time, called through function pointers. That is the
  loader itself proven end-to-end on a real third-party `.so`, which is what
  this ticket exists for.

`lib/rtl/classes.pas` gained what Synapse's HTTP layer needed on the way: the
**`Name=Value` surface on TStrings** (`Values`, `Names`, `ValueFromIndex`,
`IndexOfName`, `NameValueSeparator`). `httpsend`'s cookie jar is
`FCookies.Values[name] := v` and nothing else, so the unit could not compile at
all. Semantics were read off an FPC build of the test rather than guessed —
including two quirks nobody would have invented (a line with no separator has an
empty `Name` but its whole text as the value; an empty value deletes through
`ValueFromIndex` yet keeps `Name=` through `Values`). Regression:
`test/lib_strings_namevalue.pas`, in `lib-test`, compiles under FPC too.

### Where item (d) stops now, and it is NOT this ticket's fault

Two separate crashes, both below Track B:

1. **`uses blcksock;` segfaults before `main`.** Three lines, no SSL, no
   network. Naming `synaip` (or `synautil`) in the program's own uses clause
   FIRST makes it go away. Filed as
   [[bug-pascal-transitive-unit-crashes-at-startup-unless-named-first]] (Track
   A). `test/lib_synapse.pas` is only accidentally green — it happens to write
   `synautil` before `blcksock`.
2. With that worked around, TCP connect succeeds and **`SSLDoConnect` segfaults
   INSIDE libssl** — `call *0xb8(%r12)` with `rdi`/`rsi` both `0`, i.e. we
   handed OpenSSL a null where a context belongs. That is a marshalling or
   symbol-resolution fault on the indirect-call path, i.e. Track A again, and it
   needs its own investigation before it can be filed with a real root cause
   rather than a guess.

**Deliberately NOT added to the regression suite.** An SSL end-to-end test today
would have to name `synaip` first to survive startup, which would bake in a
workaround and hide the very bug that blocks it. It goes in when (1) is fixed.

Item (b), other-target run verification, is unchanged and still needs the cross
runners.

## 2026-08-02 (Track B) — the stale blocker, and item (d)'s real root cause

**The frontmatter blocker was stale.** This ticket sat in `blocked/` behind
`bug-cdecl-indirect-over-6-integer-args`, which is in `done/` — re-measured, a
7-argument indirect cdecl call returns the right answer. Nothing has been
holding this ticket back on that account. The other bug named in the 2026-07-31
note, `bug-pascal-transitive-unit-crashes-at-startup-unless-named-first`, is
also resolved: `uses blcksock;` alone now starts cleanly, so wall (1) is gone
and `test/lib_synapse_transitive_unit.pas` guards it.

Also stale in the body above: the Context section still says "**no
`PalDlOpen`/`PalDlSym`/`PalDlClose` primitives exist**" and that
`PalHasDynlib` is lying. Both were fixed by the 2026-07-12 update further down;
the opening text was never revised. Measured today: without the define
`PalHasDynlib` is False and `PalDlOpen` returns nil; with `-dPXX_DYNLIB_LIBC`,
`dlopen("libc.so.6")` and `dlsym("getaddrinfo")` both succeed.

**Item (d)'s second wall now has a real root cause**, which the 2026-07-31 note
explicitly deferred rather than guess at. It is NOT this ticket's loader and not
the indirect-call path:

> Driving OpenSSL 3 directly through our own `dlopen` works completely —
> `OPENSSL_init_ssl` returns 1, `TLS_method`/`TLS_client_method` resolve, and
> `TLS_client_method()` / `SSL_CTX_new()` / `SSL_new()` all return non-null.

The fault is a Pascal frontend semantics bug: a procedural variable used in a
value context has its ADDRESS taken instead of being CALLED (FPC `{$MODE
DELPHI}` calls it; verified against the FPC binary, in that mode, because that
is the mode the Synapse unit declares). So `SslMethodTLS` returns
`@TLS_method` rather than `TLS_method()`, and libssl dies dereferencing it.
Confirmed by simulation: `SSL_CTX_new(TLS_client_method())` is fine,
`SSL_CTX_new(@TLS_client_method)` segfaults exactly as observed.

Filed as [[bug-pascal-procvar-in-value-context-takes-address-instead-of-calling]]
(Track P, urgent — it silently yields a valid-looking pointer, and the idiom is
how every Delphi-family dynamic-binding layer is written). This ticket's
blocked-by now points at that, which is its ONLY remaining external blocker.

Item (b), other-target run verification, is unchanged.

## 2026-08-09 (Track B): blocker cleared, item (b) as far as this box allows

**The blocker is gone.** `bug-pascal-procvar-in-value-context-takes-address-instead-of-calling`
is in `done/`, and it was this ticket's only remaining external one. Re-tested
the idiom it broke — a proc var bound from `GetProcedureAddress` and CALLED in a
value context, which is how every Delphi-family dynamic-binding layer is written
— and it works.

**Item (b), other-target verification** — done to the limit of this machine:

| target | compiles | interpreter | `NEEDED libc.so.6` | RUN |
| --- | --- | --- | --- | --- |
| x86-64 | yes | `/lib64/ld-linux-x86-64.so.2` | yes | **yes** |
| i386 | yes | `/lib/ld-linux.so.2` | yes | **yes** (qemu) |
| arm32 | yes | `/lib/ld-linux.so.3` | yes | host has no loader |
| aarch64 | yes | `/lib/ld-linux-aarch64.so.1` | yes | host has no loader |

arm32/aarch64 cannot RUN here: `/usr/arm-linux-gnueabi` and
`/usr/aarch64-linux-gnu` contain binutils only — no `ld-linux*`, no libc — so
qemu dies at the interpreter. That is a host gap, not a pxx one, and it must not
be allowed to read as a pass.

So lib-test asserts what IS checkable per target: the emitted interpreter string
matches that architecture's and `libc.so.6` is imported. That is precisely what
item (b) doubted — the extern/dynsym emission being target-independent — and the
dynamic section backs it up: 72 bytes of relocations, three 24-byte entries, for
exactly `dlopen`/`dlsym`/`dlclose`, all three names in the string table.

**Remaining:** item (d), Synapse SSL/TLS end to end, and a real arm/aarch64 run
on a box with those sysroots (or a container). Neither is a decision — both are
work.


## 2026-08-15 (Track B) — item (d) moves: the wall was OUR errno, not the loader

Re-measured rather than trusted, and the 2026-07-31 note's second wall turns
out to have had a plainer cause than "marshalling or symbol resolution".

**The wall was `lib/rtl/sockets.pas`.** Every `fp*` wrapper returned the PAL's
raw negative errno where FPC returns `-1`, and `fpGetErrno` was a hardcoded
`5 { EIO }`. Synapse's `SockCheck` compares against `SOCKET_ERROR` (-1), so a
failed call read as a success, and `TTCPBlockSocket.Connect` with
`ConnectionTimeout > 0` — the non-blocking path every real client sets —
reported `LastError=5` against a loopback `openssl s_server` that was up and
accepting. Without the timeout the same connect worked, because that path never
consults errno, which is exactly why this hid for so long. Fixed and gated:
[[bug-b-sockets-fp-wrappers-return-raw-negative-errno-and-fpgeterrno-is-a-constant]].

**With that fixed, Synapse connects (`connect=0`)** and reaches the TLS
handshake, where it segfaults with the program counter pointing INTO THE STACK
(`0x7fffffffd7a8`, `add %al,(%rax)`) — i.e. a transfer of control to data, not
a null dereference inside libssl. So item (d) is past the wall it sat on since
2026-07-31 and is now stopped one step later, in `SSLDoConnect`.

**The debugger is unavailable for that step**, and that is its own bug: `-g` on
any program with a `TTCPBlockSocket` variable **crashes the compiler**, because
DWARF emission recurses forever on the `TTCPBlockSocket` <-> `TCustomSSL` cycle
that `blcksock.pas`'s forward declaration sets up. Reduced to 11 lines with no
library and filed as
[[bug-a-dwarf-emission-recurses-forever-on-mutually-referencing-classes]]
(Track A). Item (d) should wait for it rather than be investigated blind — the
last time this ticket guessed at a cause instead of measuring one, the guess
was wrong.

**Item (b) unchanged and still host-limited.** Re-checked today:
`/usr/arm-linux-gnueabi` and `/usr/aarch64-linux-gnu` still hold `bin` only —
no `ld-linux*`, no libc — so arm32/aarch64 still cannot RUN a dynamically
linked binary here. Compile, interpreter string and `NEEDED libc.so.6` remain
asserted for all four targets; only the run is missing, and it needs a
different box or a container.


## 2026-08-16 — item (d)'s blocker is FIXED (board maintenance, no code)

[[bug-a-dwarf-emission-recurses-forever-on-mutually-referencing-classes]] was
**resolved 2026-08-15** (`dd193ae6f`, status `done`). This ticket says item (d)
"should wait for it rather than be investigated blind" — that wait is over, and
`-g` on a `TTCPBlockSocket` program is available again, which is the tool item
(d) was missing when it stopped in `SSLDoConnect`.

Moved to `backlog/` so it can be ranked: it is no longer parked-waiting-on-a-fix,
which is what `unfinished/` means.

**Item (b) is still genuinely host-limited** and does not move: `/usr/arm-linux-gnueabi`
and `/usr/aarch64-linux-gnu` hold `bin` only — no `ld-linux*`, no libc — so
arm32/aarch64 cannot RUN a dynamically linked binary on this box. That one needs
a different machine or a container, not a decision.

## 2026-08-17 (frank3, Track B) — item (d) advances; the loader itself is now GATED

Premises re-measured first, against `pinned` **v344**.

### Item (b): unchanged, still genuinely host-limited

`/usr/arm-linux-gnueabi` and `/usr/aarch64-linux-gnu` still contain `bin` only —
no `ld-linux*`, no libc. arm32/aarch64 still cannot RUN a dynamically linked
binary on this box. Not a decision and not work: it needs a different machine or
a container.

### The DWARF blocker really is cleared

`dd193ae6f` is an ancestor of the v344 pin, and `-g` on a `TTCPBlockSocket`
program now compiles and runs. That is what let item (d) be investigated with a
debugger rather than blind, as the 2026-08-15 note asked.

### A Track B gap found and fixed on the way: `HModule`

`ssl_openssl3_lib.pas` did not compile — `unknown type: HModule` at its
`LoadLib`/`GetProcAddr` helpers. The 2026-07-20 note added `HModule` to
`lib/rtl/dynlibs.pas`, which is not enough: that unit reaches the type through
`synafpc` -> `dynlibs`, and **units do not re-export their imports
transitively** (the same fact that decided the `gtk3_c` question earlier today).

Measured where FPC actually keeps it rather than assumed: `var h: HModule`
compiles under FPC with an **empty uses clause**, so it lives in `System`. pxx
has no System unit, so it is now declared in `lib/rtl/sysutils.pas` — the unit
`ssl_openssl3_lib.pas` does use, and where this repo already fills FPC-surface
gaps (`TSysCharSet` precedent). Declared independently rather than aliased
through `dynlibs`, which is what FPC does too (`System.HModule` and
`DynLibs.TLibHandle` are separate declarations of the same width, both `PtrInt`
here, so the spellings stay assignable) — aliasing would drag `dynlibs` and
`platform` into every unit that uses SysUtils for a type most never name.

### The loader is now GATED, which it never was

`test/lib_synapse_ssl.pas`, inside the existing `external/synapse` guard in
`make lib-test`, asserts the two things that are TRUE today:

- `uses ssl_openssl3` compiles (the `HModule` regression), and
- `InitSSLInterface` + `OpenSSLVersion(0)` answer `OpenSSL 3.0.13 30 Jan 2024`.

That second one is this ticket's whole point — the dlopen loader resolving real
symbols out of a third-party `.so` we do not control — and until now it was only
ever demonstrated by hand. A stub would answer `''`; the test fails if it does.

### Item (d): past the old wall, stopped at a new one that is NOT ours to fix

With a local `openssl s_server`, the probe now reaches and fails **inside the TLS
handshake**: `connect=0`, then SIGSEGV with `rip == rax` and **`rip` inside
`[stack]`** — a tail call through a function pointer holding a stack address.
Hand-resolved symbols put it in libcrypto's certificate-verification path
(`X509_verify_cert`, reached from `SSL_get_ex_data_X509_STORE_CTX_idx`).

**The byte-identical program built with FPC completes the handshake (`ssl=0`).**
Same machine, same OpenSSL, same server, same source. So it is ours.

Filed as
[[bug-a-synapse-tls-handshake-jumps-into-the-stack-inside-x509-verify-cert]]
(Track A) with the full register/symbol evidence and, importantly, the list of
things measured NOT to be at fault: the loader, C→Pascal callbacks through a
`dlsym`'d pointer (a Pascal `cdecl` comparator drives libc's `qsort` correctly),
the socket layer, and Synapse's own callback surface.

Item (d) is therefore **blocked on Track A**, not on this ticket, exactly as it
was in the 2026-07-20 round. Parking in `unfinished/` with both remaining items
recorded: (b) needs a box, (d) needs the compiler fix.

**Not added to the suite:** a real handshake assertion. It would be red today for
a reason that belongs to another ticket, and `lib_synapse_ssl.pas` says so in its
header so the omission is visible rather than silent.
