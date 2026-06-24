# Real dynamic-library loader (`dlopen`) — PAL primitives + libc policy

- **Type:** feature / design decision (runtime infrastructure)
- **Status:** backlog
- **Owner:** — (**Track B** lead — `lib/rtl` PAL; needs Track A coordination for
  the link-libc profile / loader-vs-link decision)
- **Opened:** 2026-06-24
- **Found-by:** Synapse recon ([[feature-synapse-compile-check]]) — `dynlibs`
  stub unblocks compile but cannot actually load anything (SSL/TLS).
- **Relation:** consumed by [[feature-synapse-compile-check]] (only for the
  SSL/TLS path; the plain-HTTP path needs only the stub). Relevant to many
  future projects, not just Synapse.

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
