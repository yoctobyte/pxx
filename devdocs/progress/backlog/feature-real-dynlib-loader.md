---
prio: 45  # auto
---

# Real dynamic-library loader (`dlopen`) — PAL primitives + libc policy

- **Type:** feature / design decision (runtime infrastructure)
- **Status:** backlog
- **Owner:** — (**Track B** lead — `lib/rtl` PAL; needs Track A coordination for
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
