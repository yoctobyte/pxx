# QEMU cross-target test environment

- **Type:** chore
- **Status:** done
- **Owner:** claude
- **Opened:** 2026-06-10 (user request, prerequisite for the compile-target arc)

## Goal

Run PXX-emitted binaries for any planned CPU target (i386, aarch64, arm32,
later RISC-V) on the x86-64 dev host, so each backend's regression tests and
fixedpoint gates execute without target hardware. Scope stays Linux/Unix
userland — no bare-metal/system emulation yet.

## Decisions

- **qemu-user, not qemu-system.** User-mode emulation translates a single
  foreign binary's syscalls onto the host kernel: no VM, no kernel image,
  fast enough to run the full suite per target. System emulation is deferred
  until something needs a real foreign kernel (ESP32/bare-metal arc).
- **PXX binaries are the ideal case.** Static, syscall-only, own ELF writer —
  no target libc/sysroot (`-L`) needed. A future dynamically linked
  cross-arch test must add `QEMU_LD_PREFIX`; documented in the runner.
- **One runner indirection.** `tools/run_target.sh <arch> <binary> [args]`
  picks native execution (x86_64; i386 native-first with qemu fallback) or
  the right qemu-user binary, and passes the program's exit code through, so
  existing `test "$(...)" = ...` Makefile assertions work unchanged for any
  target.
- **binfmt registration** (qemu-user-static + binfmt-support) as convenience:
  the kernel can then exec foreign binaries directly. The runner never relies
  on it.

## Pieces

- `tools/install_qemu.sh` — one-shot sudo install + per-emulator report.
- `tools/run_target.sh` — arch-dispatching runner (above).
- `make qemu-env-check` — compiles hello, runs it through the runner's
  x86_64 path, reports which emulators are present. Manual target; joins
  `make test` only when a cross backend exists to exercise it.

## Host installation

None needed: qemu-user 8.2.2 was already installed (an earlier probe
truncated `dpkg` output and misread it as absent). `tools/install_qemu.sh`
remains for fresh hosts.

## Acceptance

- `make qemu-env-check` green: hello runs via the runner, qemu-i386 /
  qemu-aarch64 / qemu-arm all present.
- Real foreign-arch validation (an actual aarch64 binary under qemu-aarch64)
  necessarily waits for the first cross backend; the i386 backend
  (feature-target-i386, now blocked on this ticket) is the first consumer.

## Log

- 2026-06-10 — ticket opened; runner + install script + check target written;
  awaiting host qemu-user install.
- 2026-06-10 — delivered, commit d2fc574. qemu-user was already on the host;
  probe ELFs (exit 42) for i386/aarch64/arm32 all execute through
  `tools/run_target.sh`; `make qemu-env-check` green. Acceptance exceeded:
  real foreign-arch execution proven now, not deferred to the first backend.
  (Probe bug found en route: ELF32 p_offset must equal p_vaddr mod pagesize —
  map the whole file at offset 0. Future 32-bit ELF writers take note.)
