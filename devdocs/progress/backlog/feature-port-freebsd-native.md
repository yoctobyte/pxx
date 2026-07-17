---
summary: "FreeBSD/amd64 native target — raw-syscall ELF, own syscall table, carry-flag error convention, ELF brand"
type: feature
prio: 55
---

# FreeBSD native target (amd64) — raw-syscall, stays in the libc-free family

- **Type:** feature (Track A — backend/ABI/ELF/syscall emission). Portability campaign.
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-17, OS-portability mapping session. Full map in
  [`devdocs/dev/portability-axes.md`](../../dev/portability-axes.md).
- **Related:** [[feature-port-rtl-over-libc]] (NOT needed here — FreeBSD keeps raw
  syscalls), [[feature-port-openbsd-libc]] (the libc-through sibling). North star:
  [[ir-as-substrate]].

## Why FreeBSD is the cheapest first win

Same family as Linux: **raw-syscall ELF on amd64, identical argument registers**
(rdi/rsi/rdx/r10/r8/r9). Keeps the libc-free identity intact. And FreeBSD's
**linuxulator** (`linux64.ko`) runs today's *Linux* pxx binaries unmodified — a
zero-work smoke on a real BSD kernel before writing a line of code.

## What differs from Linux (the whole delta)

1. **Syscall numbers** — FreeBSD's own table (`write=4`, `exit=1`, …), not Linux's.
2. **Error convention** — FreeBSD signals an error via the **carry flag** (CF set,
   errno in rax), NOT Linux's negative-rax. *This is the real work* — every syscall
   wrapper's error check changes, not just a number swap.
3. **ELF brand** — set `EI_OSABI = ELFOSABI_FREEBSD (9)` or emit the
   `NT_FREEBSD_ABI_TAG` note so the kernel brands the binary correctly.
4. **`exit_group` → `exit`** (no thread-group exit; adjust the process-exit path).

## Plan

- Add the FreeBSD syscall-number table + carry-flag error path behind the platform
  axis (see [[project_pal_platform_axis_step1]]); `--platform=freebsd`.
- Brand the ELF in `elfwriter.inc`.
- Smoke order: (a) linuxulator runs a current Linux binary (no build change);
  (b) native `--platform=freebsd` hello-world; (c) heap/string/exception torture.

## Acceptance

- `--platform=freebsd` emits an amd64 ELF that runs **natively** on FreeBSD (qemu
  image) and produces output byte-identical to the Linux build for a scalar +
  heap/string/exception torture program.
- Linuxulator smoke logged (runs a current Linux pxx binary on FreeBSD) as the
  pre-native checkpoint.
- Gate: `make test` + self-host byte-identical (Linux default unchanged); FreeBSD run
  under qemu.

## Test infra

qemu FreeBSD image (pre-built qcow2 exists) + linuxulator. The per-OS image/runner
harness may live in a Track T clone (see portability-axes.md) — the compiler work is
here.
