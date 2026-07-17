---
summary: "UMBRELLA: abstract the target-OS axis — FreeBSD (native) + Windows (PE, Wine-tested), phased"
type: feature
prio: 55
blocked-by: [feature-port-rtl-over-libc, feature-port-freebsd-native, feature-port-windows-pe]
---

# UMBRELLA — target-OS abstraction: FreeBSD + Windows(Wine)

- **Type:** feature / umbrella (Track A — portability campaign). File-owned by A
  (backends / ELF+PE writers / ABI / syscall+libc lowering); gate = self-host
  byte-identical + `make test`, per-OS smoke under qemu/Wine.
- **Status:** backlog (umbrella; tracks its phase children)
- **Owner:** —
- **Opened:** 2026-07-17, from the OS-portability mapping session. Design + rationale:
  [`devdocs/dev/portability-axes.md`](../../dev/portability-axes.md).

## Goal

Make **target OS** a first-class axis of the compiler — the same way target CPU already
is — and land the two OSes that are *ready to abstract now*: **FreeBSD** (native,
raw-syscall ELF) and **Windows/amd64** (PE, Wine-tested). Everything is amd64 default;
other CPUs compose later, one OS column at a time.

The load-bearing insight (from portability-axes.md): the cost of a new OS is **Axis B —
object format** + per-OS kernel-reach config, *not* a new subsystem. pxx already
dynamic-imports external libraries; the campaign generalizes two things — **how the RTL
reaches the kernel** (raw syscall vs call a stable system DLL/so) and **which object
format** it writes (ELF today, PE new).

## Phases

Each phase is an independently-useful, already-filed child ticket. The abstraction is
*built by its first consumers*, not as scaffolding-without-a-user.

- **P0 — kernel-reach abstraction.** [[feature-port-rtl-over-libc]] — a lowering switch:
  emit raw `syscall` (Linux/FreeBSD) vs call a stable platform library
  (OpenBSD/Windows/macOS). The enabler for every non-raw-syscall OS. *Windows depends on
  it; FreeBSD does not.*
- **P1 — FreeBSD/amd64 native.** [[feature-port-freebsd-native]] — raw-syscall ELF: own
  syscall table + **carry-flag** error convention + ELF brand. Smallest new surface, so
  it *proves the OS axis end-to-end* (per-OS config table, `--platform` selection) with
  a known-good kernel. Free pre-smoke: FreeBSD linuxulator runs today's Linux pxx
  binaries unmodified.
- **P2 — Windows/amd64 PE (Wine-tested).** [[feature-port-windows-pe]] (new PE/COFF
  writer + **MS x64 ABI** + CRT-free ~10-symbol kernel32/ntdll binding) +
  [[feature-t-windows-wine-harness]] (the zero-VM test bed: wine runner + mingw-w64
  differential oracle). The big rock — Axis B, not runtime.

## Adjacent — NOT in this umbrella's active scope

- **OpenBSD** [[feature-port-openbsd-libc]] — *falls out of P0 for free* (route RTL
  through libc.so → `pinsyscalls` satisfied by construction). Related, but its own
  ticket; not a gate for this umbrella (user scoped this to FreeBSD + Windows).
- **macOS** [[feature-port-macos]] — **blocked** on Apple hardware (Mach-O + signing +
  libSystem, untestable otherwise). Explicitly out until hardware exists.

## Abstraction shape (summary — full form in portability-axes.md)

Two independent axes, made first-class:

| axis | choices | pxx today |
| --- | --- | --- |
| A — kernel reach | raw syscall \| call a stable system library | both exist (raw-syscall RTL; C-lib import via PLT) |
| B — object format | ELF \| PE \| Mach-O | ELF only |

Per-OS config = { syscall table | libc-symbol map, error convention (neg-rax /
carry-flag / errno), object format, brand/interp, entry model }. `--platform=<os>`
selects it. Raw-syscall default (Linux) stays byte-identical.

## Acceptance (umbrella)

- P0 + P1 + P2 all resolved and green.
- `--platform=freebsd` binary runs natively on FreeBSD (qemu); `--platform=windows`
  PE runs under Wine — both byte-identical program OUTPUT to the Linux reference for a
  scalar + heap/string/exception torture program.
- Linux default self-host stays byte-identical throughout (every phase lands behind the
  flag, incrementally, never a long-lived branch).

## Explicit non-goals

- Not other CPUs yet (amd64 columns first).
- Not macOS (blocked).
- Not a rewrite — raw-syscall Linux/FreeBSD stay raw; the abstraction is additive.
