---
summary: "FreeBSD/amd64 native target — raw-syscall ELF, own syscall table, carry-flag error convention, ELF brand"
type: feature
prio: 55
status: blocked
blocked-by: [feature-t-freebsd-image-and-runner]
---

# FreeBSD native target (amd64) — raw-syscall, stays in the libc-free family

- **Type:** feature (Track A — backend/ABI/ELF/syscall emission). Portability campaign.
- **Status:** blocked on [[feature-t-freebsd-image-and-runner]] — no FreeBSD kernel is reachable from plexus (no qemu, no image), and this ticket's own plan puts a linuxulator smoke test FIRST, before any code. The compiler work is ready to start the moment a kernel is.
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

## 2026-08-20 — not started: the test infra this needs is not on plexus

Reached as the top Track A item and **deliberately not claimed**. The blocker is
environmental, not a design question, so it is recorded here rather than
escalated to Track U.

Measured on plexus (the dev box, `frank1`):

- `qemu-system-x86_64` — **not installed**.
- No FreeBSD image anywhere obvious (`~`, `/var/lib/libvirt/images`). The "Test
  infra" section above says "pre-built qcow2 exists"; it does not exist on this
  machine. It may exist on another box, or the claim may be stale — worth
  confirming before anyone plans around it.

Both acceptance criteria are unrunnable here: the native `--platform=freebsd`
run *and* the linuxulator smoke need a FreeBSD kernel. The ticket's own plan
puts that smoke **first**, ahead of writing any code, which is the right order —
it is the cheap proof that the ELF layout is already acceptable to the kernel.

### Why the verifiable subset was not landed either

Two of the four deltas could be written and partially checked without FreeBSD —
the syscall-number table, and the ELF brand (`EI_OSABI = 9`, assertable straight
out of the emitted header). The third cannot: the **carry-flag error
convention** is the item this ticket itself calls *"the real work"*, it touches
every syscall wrapper's error check, and nothing on this box can tell a correct
carry-flag path from a wrong one.

Landing the easy two would leave a `--platform=freebsd` that emits a
correctly-branded ELF whose every syscall error check is untested — a
half-applied Track A change, which `CLAUDE.md` flags as the critical case
because it is the shape that quietly poisons the shared ground. Better an
unstarted ticket than a platform that looks present and is not.

**What unblocks it:** qemu plus a FreeBSD/amd64 image on whichever box runs it,
or confirmation of where the existing qcow2 lives. That is Track T-shaped
infrastructure work (per `portability-axes.md`, the per-OS image/runner harness
may live in a Track T clone); the compiler work here is ready to start the
moment a kernel is reachable.
