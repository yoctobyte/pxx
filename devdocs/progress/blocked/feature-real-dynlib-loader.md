---
prio: 45  # auto
blocked-by: [bug-cdecl-indirect-over-6-integer-args]
---

# Real dynamic-library loader (`dlopen`) — PAL primitives + libc policy

- **Type:** feature / design decision (runtime infrastructure)
- **Status:** working
- **Owner:** trackB-agent
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
