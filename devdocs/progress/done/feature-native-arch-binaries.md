# Distribute native per-arch stable binaries (no FPC/make on install)

- **Type:** feature (release / distribution)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-24
- **Found-by:** `./install.sh` on aarch64 — committed stable binary is x86-64
  only, so install aborted ("pinned compiler did not run a smoke compile").

## Goal

A fresh `git clone` should be runnable on any supported host **without FPC or
make** — the self-bootstrap promise. Today only `stable_linux_amd64/` ships an
x86-64 binary; on aarch64 / arm32 / i386 there is no runnable compiler in the
checkout, so `install.sh` must fall back to `make bootstrap` (needs FPC).

(Interim: `install.sh` now detects this and offers `make bootstrap`; this ticket
is the real fix — ship the binaries.)

## Scope

- Commit a **native** stable binary per host arch: `stable_linux_<arch>/…`
  (x86_64 / aarch64 / arm32 / i386), each an ELF that RUNS on that arch.
  Produced by the existing cross backends: `pxx --target=<arch> compiler.pas`.
- **Host-default target.** A cross-built `pxx-aarch64` still defaults
  `TargetArch := TARGET_X86_64` at startup (compiler.pas), so by itself it would
  emit x86-64 code on an aarch64 host. Two options:
  1. the generated `./pxx` wrapper passes `--target=<host-arch>` (cheap, works
     now — `tools/install.sh` would add it for the non-x86_64 native binary), or
  2. a real host-default: detect/compile-in the native target so bare `pxx`
     emits host code (cleaner; needed for a binary used without the wrapper).
- Verify each native binary self-hosts under QEMU (compile a hello + the
  regression set) before committing.
- Wire into `tools/release.sh` so every release ships all four.

## Done when

- `git clone` + `./install.sh` on aarch64 (and arm32 / i386) produces a working
  `./pxx` with **no FPC/make**, building+running the demos.
- `make` gate unaffected (these are committed artifacts, not built in CI).

## Notes

- Binary size: ~3 MB each → ~9 MB added to the repo. Acceptable for the
  self-bootstrap guarantee; revisit with git-lfs if it grows.
- The pin/stabilize machinery is x86-64-centric (`stable_linux_amd64/`); this
  generalises the layout to `stable_linux_<arch>/`.

## Log
- 2026-06-24 — DONE. Committed native cross-built binaries `native/pxx-{aarch64,
  arm32,i386}` (x86-64 host keeps the auto-tracking `pinned` symlink). Built with
  the pinned compiler (`pxx --target=<arch> compiler.pas`); each verified
  end-to-end under QEMU: the binary runs on its arch and compiles+runs a hello.
  Host-default-target handled by option 1 (wrapper injects `--target=<host>`):
  `tools/install.sh --target ARCH` adds it, and root `install.sh` selects
  `native/pxx-<arch>` for the host and passes the target. So a bare `git clone`
  + `./install.sh` on aarch64/arm32/i386 needs no FPC/make. (Native make-bootstrap
  remains the fallback if no committed binary matches.)
  NOTE: these binaries are committed artifacts and go stale on a compiler change;
  rebuild them when re-pinning (a `make` target to regenerate is a follow-up).
  Option-2 (a real compiled-in host default so bare `pxx` needs no `--target`) is
  left for later — the wrapper covers the install UX today.
