---
summary: "OpenBSD/amd64 target — route RTL through libc.so; pinsyscalls satisfied by construction"
type: feature
prio: 50
blocked-by: [feature-port-rtl-over-libc]
---

# OpenBSD native target (amd64) — libc-through, ELF

- **Type:** feature (Track A — linking/ELF/RTL lowering). Portability campaign.
- **Status:** backlog (blocked on [[feature-port-rtl-over-libc]])
- **Owner:** —
- **Opened:** 2026-07-17, OS-portability mapping session. Full map in
  [`devdocs/dev/portability-axes.md`](../../dev/portability-axes.md).

## Why it's small (once RTL-over-libc exists)

OpenBSD forbids raw syscalls from arbitrary text: `msyscall(2)` (6.4) →
**`pinsyscalls`** (7.3/7.4) let the kernel kill any `syscall` instruction not issued
from the pinned libc site. This is **anti-ROP call-site allowlisting, not signing**
(see portability-axes.md for the honest rationale — it is a defensible mitigation, not
a flaw).

Route the RTL through **libc.so** and the whole problem evaporates: the pxx binary
emits **zero `syscall` instructions**, so every syscall originates inside OpenBSD's own
libc — exactly and only what `pinsyscalls` permits. **Compliant by construction; no pin
table, no `msyscall` call needed.** And it's still ELF, which pxx already writes and
dynamic-imports — so this is mostly *configuration* on top of [[feature-port-rtl-over-libc]].

## What differs

- **Interp** → `/usr/libexec/ld.so`; **`DT_NEEDED`** → OpenBSD `libc.so.<maj>.<min>`.
- Static-PIE is OpenBSD's norm; emit position-independent, or dynamic-link (simpler).
- RTL primitives lower to libc symbols (from [[feature-port-rtl-over-libc]]); errno via
  OpenBSD's `__errno`.
- **No Linux compat on OpenBSD** (removed ~2014) — there is no linuxulator escape
  hatch; testing is native-only.

## Acceptance

- An OpenBSD amd64 ELF that dynamic-links libc.so, runs natively (qemu, autoinstall
  image), and whose disassembly contains **no raw `syscall`** — proving pinsyscalls
  compliance structurally.
- Output byte-identical to the reference for a scalar + heap/string/exception torture.
- Gate: `make test` + self-host byte-identical (Linux default untouched); OpenBSD run
  under qemu.

## Test infra

qemu OpenBSD via `autoinstall` (no pre-built qcow2). Runner may live in the Track T
clone.
