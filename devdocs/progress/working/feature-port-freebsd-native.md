---
summary: "FreeBSD/amd64 native target — raw-syscall ELF, own syscall table, carry-flag error convention, ELF brand"
type: feature
prio: 25
status: working
blocked-by: []
track: A
---

# FreeBSD native target (amd64) — raw-syscall, stays in the libc-free family

- **Type:** feature (Track A — backend/ABI/ELF/syscall emission). Portability campaign.
- **Status:** blocked on [[feature-t-freebsd-image-and-runner]] — no FreeBSD kernel is reachable from plexus (no qemu, no image), and this ticket's own plan puts a linuxulator smoke test FIRST, before any code. The compiler work is ready to start the moment a kernel is.
- **Owner:** pxx2-bsd
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

qemu FreeBSD image (**FreeBSD.org publishes pre-built qcow2 VM images**, unlike
OpenBSD — cf. the parallel line in [[feature-port-openbsd-libc]], *"qemu OpenBSD
via `autoinstall` (no pre-built qcow2)"*, filed in the same commit) +
linuxulator. The per-OS image/runner harness may live in a Track T clone (see
portability-axes.md) — the compiler work is here.

> **Wording clarified 2026-08-28 by Track T (pxx-a5).** This line previously
> read *"(pre-built qcow2 exists)"* and was read below, and in
> [[feature-t-freebsd-image-and-runner]], as a claim that an image existed **on
> our infrastructure**. It never said that: it is one half of an
> obtain-the-image comparison with OpenBSD. The sentence was true; its subject
> was upstream. Nothing about the plan changed — only the reading it invites.

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

> **Resolved 2026-08-28 by Track T (pxx-a5): neither.** Re-measured on plexus
> (nothing changed in eight days — no `qemu-system-*` of any kind, no libvirt,
> no `*.qcow2` / `*.iso` / `*.img` anywhere reachable). The claim is **not
> stale and not about another box**: it is a true statement about what
> FreeBSD.org publishes, misread as an inventory. See the clarified wording
> above and [[feature-t-freebsd-image-and-runner]] for the full measurement.
> **The practical consequence is unchanged** — there is still no kernel to boot
> here, and this ticket stays blocked — but the lead "go find the existing
> image" is closed, and nobody should spend time on it again.

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

## 2026-11-12 (pxx2-bsd) — claimed; the kernel exists now, and the linuxulator smoke passes

Owner, 2026-11-12, on being asked which port to take: *"i thought freebsd was
the easiest one?"* -- and then *"continue working on BSD / other kernel support"*.
Taken as lifting the 2026-09-01 BSD demotion for this ticket too (recorded in
`the-goal-cross-cross.md` beside the libc-family note).

**Infra (unblocks this; does the job of `feature-t-freebsd-image-and-runner`):**
FreeBSD 15.1-RELEASE amd64, the official BASIC-CLOUDINIT ufs qcow2, under
qemu/KVM on plexus in `/data/vm/freebsd` (root is 99% full -- never on `/`).
`start.sh` boots it headless with ssh on 127.0.0.1:2223; `run.sh <bin> [args]`
copies a binary in and relays stdout/stderr/exit. The cloud-init seed did NOT
install the key (no nuageinit output on the console); `setup.py` does it once
over the serial console (root has no console password on these images, and
FreeBSD's sshd needs `PermitRootLogin prohibit-password`).

**Smoke (a) — linuxulator, PASSES.** `kldload linux64`; then
`test/test_rtl_libc_torture.pas` built by the Linux compiler (default, raw
syscalls) prints byte-identical output and exits 0 on FreeBSD -- but only after
`brandelf -t Linux`. Unbranded it is `Exec format error`: pxx writes
`EI_OSABI = 0` (SVR4) and no ABI note, so FreeBSD's static-binary brand
fallback does not pick Linux. Setting `EI_OSABI = 3` (ELFOSABI_LINUX) on Linux
output would make Linux pxx binaries run under linuxulator with no user step.


## 2026-11-12 (pxx2-bsd) — native `--os=freebsd` runs; torture output byte-identical

**Design changed from this ticket's plan, deliberately.** The plan was a
FreeBSD syscall table plus a carry-flag error path at every wrapper. Measured
first: the RTL makes 98 distinct Linux calls over ~190 sites, and they carry
Linux *flag bits and struct layouts* too (open/mmap flags, `stat`, `dirent`,
`stack_t`, clock ids, errno 35+), not just numbers. A number table alone would
not have been enough. Instead:

- `--os=freebsd` (alias `--platform=freebsd`) routes every kernel entry through
  the shared out-of-line thunk `--rtl-libc` already uses (`EmitSyscall` ->
  `EmitLibcSyscallThunk`). In FreeBSD mode the thunk makes a direct call to
  `PXXFbsdSyscall` instead of libc's `syscall()`, and skips the errno fixup.
- `compiler/builtin/fbsdabi.pas` (new, pulled only for `--os=freebsd`, like
  `wasibackend`) is a small Linux-ABI translator: number map, open/mmap/AT_/clock
  flag translation, `stat`/`statx`/`dirent64` conversion, `sigaltstack` field
  order, `arch_prctl` -> `sysarch`, `brk` emulated over a MAP_GUARD reservation
  (FreeBSD cannot answer `brk(0)`), `uname` via sysctl, errno 35..97 mapped back.
  The kernel entry is an assembler routine (carry -> -errno). Every constant was
  read from FreeBSD 15.1's headers / offsetof on the VM, not from memory.
- The carry-flag convention is handled ONCE, in that routine.
- `EI_OSABI = 9`. Nothing else in the ELF needed to change.
- The RTL is untouched and the Linux default is unchanged (all new paths are
  gated on `TargetKernel = KERNEL_FREEBSD`).

**Results (FreeBSD 15.1-RELEASE amd64 under qemu/KVM):**

| program | result |
| --- | --- |
| hello-world | runs, exit 0 |
| `test/test_rtl_libc_torture.pas` (scalars, dynarray, AnsiString, class, raise/except, file write/read/delete) | stdout + exit code **byte-identical** to the Linux build |

`tools/syscall_scan.py` finds 2 raw kernel entries: the translator's own, and
the `rt_sigreturn` stub (`syscall_raw`, never reached -- see below).

**Tests:** `test-core` gains a build-only check (OSABI 9, exactly 2 kernel
entries -- a third would mean a site bypassed the thunk and would issue a Linux
number on FreeBSD). `make test-freebsd` runs on the VM and diffs against Linux;
not in `test` because it needs the VM. VM tooling: `tools/vm/freebsd.sh
fetch|start|run|stop` (image under `$PXX_VM_DIR`, default `/data/vm`).

**Phase 1 limits (each answers honestly rather than wrongly):**
- ~~**Signals:**~~ resolved below (2026-11-12, phase 2). Was: `rt_sigaction` / `rt_sigprocmask` are accepted and ignored, so a
  hardware fault (nil deref, div by zero trap) kills the process instead of
  raising an exception, and Ctrl-C takes the default action. Doing it properly
  needs FreeBSD `sigaction` (struct differs), FreeBSD's own signal trampoline
  (no SA_RESTORER), and the handler reading FreeBSD's `ucontext`/`siginfo`
  layout. The `rt_sigreturn` raw stub must then go (Linux 15 = FreeBSD chmod).
- **Threads:** `clone` -> ENOSYS. Needs `thr_new` + `_umtx_op` for futex.
- ~~**Environment:**~~ resolved below (translator answers `/proc/self/environ`).
- **termios:** only `isatty` (TCGETS); TCSETS* is a no-op.
- **Not yet:** sockets, file locks, futex, `pidfd`, `epoll`/`timerfd` (kqueue).
  Unmapped calls answer -ENOSYS.
- **Other frontends:** only the Pascal frontend pulls `fbsdabi`; C / NilPy
  drivers do not yet (same shape as `bug-a-a-frontend-cannot-see-that-a-backend-
  calls-library-routines-it-never-mentions`). **Resolved** below (C and NilPy).

## 2026-11-12 (pxx2-bsd) — environment works; an intermittent argc bug found and fixed

- **Environment: resolved** (was a phase-1 limit above). Four readers (sysutils,
  crtl, pylib, the compiler's own PxxEnvLoad) all read `/proc/self/environ`.
  Rather than teach each about FreeBSD, the translator answers that path like
  linprocfs would: `open`/`openat` of it returns an anonymous shm fd
  (`shm_open2(SHM_ANON)`, `ftruncate`d -- a shm object does not grow on write)
  holding `sysctl kern.proc.env`, which is already in /proc's NUL-separated
  format. `readlink("/proc/self/exe")` answers from `kern.proc.pathname`.
- **Entry stack, found by running ParamStr 60 times:** FreeBSD passes the
  argc/argv/envp block in `rdi` and starts `rsp` at `((block-8) & ~15) + 8`,
  i.e. 8 BELOW argc whenever the randomised block address is 16-aligned.
  `ParamCount` read -1 on about half of all runs; the torture test never
  noticed because it reads no argv. Fixed with `mov rsp, rdi` as the image's
  first instruction under `--os=freebsd` (compiler.pas, before the TLS install,
  which clobbers rdi), giving every entry stage the Linux layout. 60/60 runs
  correct after. Moving only the BSS_INITIAL_RSP store to rdi does NOT work:
  the TLS install runs first and its syscalls clobber rdi.
- `test/test_os_env.pas` (env value, unset var, count, argv0, argc + args) is in
  `make test-freebsd`, run 8 times against the Linux build's output.
  `tools/vm/freebsd.sh run` forwards `PXX_TEST_*` variables.

## 2026-11-12 (pxx2-bsd) — C and NilPy frontends

- `PullKernelAbiUnit` (frontend_prologue.inc) pulls `fbsdabi` for every
  non-Pascal driver: called from `PullTargetRuntimeUnits` (the nine skeleton
  drivers), the C driver (after pxxcio) and the NilPy driver (after builtin).
  Before this a C or NilPy `--os=freebsd` compile stopped with
  "PXXFbsdSyscall not found".
- The C entry stub ended with a raw `mov eax, 231; syscall` (exit_group after
  `main` returns) -- FreeBSD's 231 is not exit. Under `--os=freebsd` it now
  goes through `EmitSyscall` (the thunk). Found by `syscall_scan --list`: three
  entries where two are expected.
- `test/c_os_freebsd_runtime.c` (getenv, malloc, fopen/fprintf/fscanf, argv,
  `return 3` as exit status) and `test/os_freebsd_runtime.py` (dict, sorted,
  sys.argv, os.environ) are in `make test-freebsd`, diffed against the Linux
  build: identical, exit status included. test-core's build-only check also
  scans the C binary for exactly two kernel entries.
- Linux output byte-identical to a HEAD-built compiler for Pascal, C and NilPy,
  default and `--rtl-libc`.

## 2026-11-12 (pxx2-bsd) — signals, wait status, and the FreeBSD ABI note

- **rt_sigaction** never hands FreeBSD the program's handler. It records it
  (`FbLxHandler`, by FreeBSD signal number) and installs `FbSigEntry`, which
  builds a Linux `siginfo_t` (si_code mapped: SI_USER 0x10001 -> 0 etc., the
  swapped FPE_INTDIV/INTOVF) and a Linux `ucontext_t` (gregs copied from
  FreeBSD's mcontext order, offsets measured) on its own stack, calls the
  handler as SysV C, and copies the 18 gregs back -- so the PC/SP rewrites
  that turn a fault into a raise work unchanged. It returns into FreeBSD's
  own sigcode trampoline; the program's SA_RESTORER stub is never used
  (the raw rt_sigreturn stays, unreached, as the second kernel entry).
  Flags and masks translated both ways; old action reported in Linux shape.
- **rt_sigprocmask, rt_sigpending, rt_sigtimedwait, rt_sigsuspend** translate
  (how 0..2 -> 1..3; 64-bit Linux mask <-> 128-bit sigset_t with the signal
  renumbering). Linux realtime 32..64 -> FreeBSD 65..97.
- **wait4**: the wait status carries signal numbers (termsig bits 0..6,
  stopsig bits 8..15) and FreeBSD's "continued" is 0x13, Linux's 0xffff;
  translated. WCONTINUED 8 -> 4.
- **NT_FREEBSD_ABI_TAG note** (PT_NOTE, osreldate 1500000) on every
  `--os=freebsd` image, between the program headers and the code. Without it
  the kernel treats the binary as pre-7.0: with machdep.prot_fault_translation
  at its default (auto) a stack-guard fault arrived as SIGBUS, not SIGSEGV,
  and test_stack_overflow_raise died.
- `tools/vm/freebsd.sh run` sets `ulimit -s 8192` (Linux's default; FreeBSD's
  512 MB made the stack-overflow test take 11 s) and uploads beside-and-renames
  (a timed-out earlier binary kept /tmp/pxxbin busy).
- `make test-freebsd` now also runs, diffed against the Linux build:
  test_signal_pc_rewrite, test_signal_sp_rewrite, test_stack_overflow_raise,
  test_float_exception_mask, lib_signals_fpc, c_crtl_signal_and_wait,
  c_crtl_signal_dispositions. All identical. test-core checks the note.
- Linux output byte-identical to the previous compiler (Pascal, C, NilPy,
  default and --rtl-libc).
- **Next:** the posix platform backend issues ~70 syscalls and the translator
  still answers -ENOSYS to a batch of them (getrusage, getpgid/setpgid,
  getsid, get/setpriority, fchmod/fchown(at), linkat, symlinkat, mknodat,
  fdatasync, sync, truncate, get/setitimer, utimensat, get/setgroups, times,
  vfork, clock_settime). Then threads (thr_new, _umtx_op).
