# Kernel-matrix bootroom: one static PXX binary, swept across many Linux kernels

- **Type:** feature (harness + demo) — **Track E** (Examples/apps; file-ownership Track B). Linux `/init` backend of [[feature-demo-portable-userland]].
- **Status:** rainy-day 
- **Owner:** — (Track B)
- **Opened:** 2026-06-21
- **Relation:** leans on the existing QEMU harness (ESP work,
  [[project_esp_bare_boot_done]]) and the cached-download pattern from
  `tools/install_cross_sysroot.sh` (`~/.cache/pxx-cross`). Demonstrates the
  syscall-only payoff: a libc-free PXX binary is the ideal subject for an
  isolated kernel A/B test because nothing between app and kernel shifts.

## The idea

A PXX binary that uses only raw syscalls (no libc, no `ld.so`, static ELF) talks
to the single most stable ABI in Linux: the syscall ABI ("we do not break
userspace"). So the same binary boots — unchanged — on kernels spanning many
years. Flip the usual frame:

- **binary = constant, kernel = variable** (normally people pin the kernel and
  vary the binary; we pin the binary and sweep kernels).

Two independent axes fall out:

- **Correctness:** kernel must NOT matter. Same binary → same output across
  kernels. A divergence = a kernel bug or an unstable syscall we shouldn't use.
  Cheap regression net for our syscall layer.
- **Performance:** kernel WILL matter — and that's the interesting signal.
  Scheduler eras (O(1)→CFS→EEVDF), mm changes, vDSO fast paths, spectre-era
  slowdowns. Our code held constant = a clean measurement of *kernel* deltas.
  Almost nobody can do this cleanly because their userland (libc/distro) shifts
  too. We can, because we have none.

**Floor rule:** the oldest bootable kernel = the newest syscall we touch.
`read/write/mmap/exit/brk` → very old; `epoll` → 2.6; `io_uring` → 5.1. The
syscall budget chosen = how far back the binary reaches.

## MVP scope (do this first)

- **x86-64 only.** 3–4 modern kernels (e.g. 4.x / 5.x / 6.x).
- Boot each, run one PXX binary as `init`, capture serial output.
- **Correctness:** diff outputs across kernels (must match).
- **Performance:** rough timing table (wallclock + in-binary rdtsc, many runs).
- **No compiler change** — this is a harness + a PID-1-shaped demo binary. Pure
  Track B.

## Initial app (the payload)

Start simple, grow:

1. **sysinfo / proc-lister** (suggested first): open and dump `/proc/version`,
   `/proc/cpuinfo`, `/proc/meminfo`, `/proc/uptime` via raw `open/read/write`.
   Tiny syscall budget → very old floor. Doubles as "what kernel am I on" proof.
2. **microbench:** tight loops over `getpid`/`clock_gettime`(vDSO)/`mmap+munmap`/
   `write` to `/dev/null`; report cycles per op. This is the per-kernel perf
   signal. Use rdtsc inside the binary (TCG wallclock is noisy; prefer KVM).
3. **Bonus — framebuffer:** `open("/dev/fb0")`, `mmap`, draw. NICE-TO-HAVE,
   deferred: not uniform across kernels/QEMU machine models (needs a fb device
   in the guest: `-vga std` + `fbcon`, or simpledrm; varies by version). Keep it
   off the MVP critical path; add as an optional payload once the matrix works.

## Components

1. **PXX binary = `/init`** — static x86-64 ELF, raw syscalls only. PID-1-safe:
   do NOT bare `exit` (kernel panics on init death). End with the `reboot`
   syscall (`LINUX_REBOOT_CMD_*`), or `exit` + QEMU `-no-reboot` `panic=-1` so
   the kernel reboots, QEMU dies, harness collects the run. Emit a clear
   end-marker on serial before shutting down so the harness knows it finished
   (vs hung).
2. **initramfs** — cpio (`newc`) generated at test time, one binary inside.
   NEVER committed. `… | cpio -o -H newc` (or a tiny gen-initramfs helper).
3. **Kernel acquisition (the real practical problem)** — NO binary blobs in the
   git tree. Mirror `install_cross_sysroot.sh`:
   - a `tools/fetch_kernels.sh` that downloads **checksum-pinned** kernels into
     `~/.cache/pxx-kernels/`.
   - source = Ubuntu mainline PPA `.deb` (extract `bzImage`), or build minimal
     vanilla once and cache. Only the script + pinned hashes are committed.
4. **QEMU run:**
   ```
   qemu-system-x86_64 -kernel $K -initrd $IRD -nographic -no-reboot \
     -append "console=ttyS0 panic=-1 init=/init"
   ```
   (add `-enable-kvm` when available for honest timing). Scrape serial = output.
5. **Harness** — matrix loop over cached kernels: boot each, collect serial,
   diff outputs (correctness gate), table the timings (perf report). Likely a
   `make kernel-matrix` target + a script under `tools/`.

## Genuine hard parts (work, not blockers)

- Reproducible kernel fetch without blobs → solved by the cache+checksum pattern
  already in the repo.
- PID-1 clean shutdown so QEMU actually exits (don't hang CI) — reboot syscall /
  `panic=-1` + `-no-reboot`, plus a serial end-marker + harness timeout.
- Timing noise under QEMU TCG — prefer KVM; otherwise rdtsc + many iterations,
  report medians. Treat MVP perf numbers as indicative, not precise.

## Deferred / later (cool, out of MVP)

- **Ancient kernels (down to ~1.0):** needs i386 + an **a.out** backend (ELF
  support postdates 1.0) + a 1.0-era syscall subset. PXX has the i386 backend
  but no a.out emitter — that emitter is the only missing compiler piece, and
  it's a separate ticket if we ever want the "runs on kernel 1.0" stunt.
- i386 matrix; cross-arch (same source, different arch kernels).
- Exotic configs: PREEMPT_RT, different schedulers, mitigations on/off as a perf
  axis.
- Framebuffer payload (see above).

## Log
- 2026-06-21 — filed (Track B) from a design discussion on the syscall-only /
  "application on a floppy" model. Core insight: kernel syscall ABI is the
  stable rock; libc/userland is the churn — a libc-free PXX binary turns that
  stability into a clean kernel-sweep test rig.
