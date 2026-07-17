---
summary: "macOS/arm64 target — BLOCKED: needs Apple hardware+software (Mach-O + mandatory signing + libSystem)"
type: feature
prio: 20
---

# macOS native target — BLOCKED on Apple hardware

- **Type:** feature (Track A — new object format + ABI + signing). Portability campaign.
- **Status:** **blocked** — external constraint, not a ticket dependency.
- **Owner:** —
- **Opened:** 2026-07-17, OS-portability mapping session. Full map in
  [`devdocs/dev/portability-axes.md`](../../dev/portability-axes.md).

## Why blocked (the constraint, explicit)

macOS is the outlier on **both** axes and is the only target that is *untestable
without Apple hardware*:

- **Mach-O** object format — a new writer (pxx writes ELF only).
- **Mandatory code-signing on Apple Silicon** — even an ad-hoc signature
  (`codesign -s -`) is required or the kernel refuses to `exec`. Not optional.
- **No static libSystem** — Apple removed it; you must dynamically link libSystem,
  which is the *only* supported syscall boundary (numbers change between releases).
- **No cheap/legal emulation** — `darling` (a Wine-like layer) is far less mature than
  Wine, especially on Apple Silicon; qemu-macOS is license-gray and painful.
  Realistically needs a real Mac.

So macOS is **large to implement AND impossible to verify** without the hardware. Both
facts rank it dead last, independent of the rest of the campaign.

## Unblock condition

Apple hardware + a signing identity (ad-hoc is enough for local run) available to the
project. Until then this stays in `blocked/`. When it unblocks, it also depends on the
libc-call lowering ([[feature-port-rtl-over-libc]]) and adds a Mach-O writer + signing
step.

## Not now

Do **not** start speculative Mach-O work before the hardware exists — untestable output
is unverifiable output, and the campaign has three achievable targets ahead of it
([[feature-port-freebsd-native]], [[feature-port-openbsd-libc]],
[[feature-port-windows-pe]]).
