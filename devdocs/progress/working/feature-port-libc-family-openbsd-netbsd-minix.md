---
track: A
prio: 60
type: feature
status: working
owner: pxx2-bsd
created: 2026-11-12
found-by: owner + pxx2 session
blocked-by: []
tags: [portability, openbsd, netbsd, minix, rtl-libc, platform-backend]
summary: "THE LIBC FAMILY PORT, as one plan: OpenBSD first, then NetBSD, then Minix 3, all through the system libc. Owner ruling 2026-11-12 lifts the 2026-09-01 'Linux only' demotion for this work ('quite a lot of work, but no real bears on the road ... let's start working'). Two families, not five ports: raw-syscall = Linux + FreeBSD (feature-port-freebsd-native); through-libc = everything else, this ticket. KEY FINDING that sizes it: today's --rtl-libc calls libc syscall(nr,...) with LINUX numbers, so it proves the PLT path and nothing else -- OpenBSD removed syscall(2) (verify the release on the VM), NetBSD/Minix have it with their own numbers, and every Linux constant and struct layout rides along unchanged. The real work is a named-libc platform backend plus per-OS constants and structs. Surface measured 2026-11-12: 98 distinct SYS_ calls over ~190 RTL sites, 129 of them in lib/rtl/platform/posix/platform_backend.pas; the compiler itself emits ~9 kinds directly. FIRST SPIKE: OpenBSD xonly (execute-only text, 7.3+) against pxx's section-less ELF -- the one item that could force a layout change."
---

# The libc family: OpenBSD, NetBSD, Minix 3 through the system libc

## Ruling (owner, 2026-11-12)

The 2026-09-01 "Linux only, BSD demoted to 25" ruling in
`devdocs/dev/the-goal-cross-cross.md` is lifted **for this port**. Recorded
there too, so a ranker reading only that file does not re-demote it.

Framing agreed in session: *two families, split by how you reach the kernel*.

| family | OSes | ticket |
| --- | --- | --- |
| raw syscall | Linux, FreeBSD (DragonFly nearly free) | `feature-port-freebsd-native` |
| through libc | OpenBSD, NetBSD, Minix 3, later macOS | **this one** |

Supersedes the sizing in `feature-port-openbsd-libc` (which assumed the
lowering was "mostly configuration"); that ticket stays as the OpenBSD
acceptance record and is closed by step 3 below.

## Why `--rtl-libc` alone does not port

`--rtl-libc` routes every kernel entry through one thunk that calls libc's
`syscall(nr, ...)` with the **Linux** syscall number. That proves pxx can
synthesise libc imports and call through the PLT. It carries nothing across:

- OpenBSD removed `syscall(2)` from libc after pinsyscalls (believed 7.5 —
  verify on the VM).
- NetBSD and Minix still have `syscall()`, but with their own numbers.
- Every Linux constant (errno, open/mmap flags, signal numbers, ioctl codes)
  and struct layout (`statx`, `dirent64`, `termios`, `sigaction`, `sockaddr`)
  passes through unchanged.

## Surface, measured 2026-11-12 (HEAD 30386bbbce)

- **98 distinct `SYS_*`** across ~190 `__pxxrawsyscall` sites in `lib/`.
  - `lib/rtl/platform/posix/platform_backend.pas` **129** — already a backend
    seam beside `wasi/` and `esp/`.
  - `scheduler.pas` 27, `palthread.pas` 14, `palparallel.pas` 7,
    `sockets.pas` 5, `palfutex.pas` 4, rest 1 each.
- **Compiler-emitted directly:** `SYS_WRITE` (30 refs), `READ`, `OPEN`,
  `CLOSE`, `BRK`, `MMAP`, `EXIT`, `EXIT_GROUP`, `LSEEK`; plus the four that
  cannot go through a call: `rt_sigreturn`, `clone`, `arch_prctl` (GS),
  thread `exit` (`decide-openbsd-pinsyscalls-vs-the-rt-sigreturn-residual`).

Re-measure:

```
grep -rhoE "__pxxrawsyscall\(\s*SYS_[A-Za-z_0-9]+" lib | sed 's/.*(\s*//' | sort -u | wc -l
grep -rhoE "\bSYS_[A-Z_0-9]+" compiler/*.inc compiler/*.pas | sort | uniq -c
```

## The work, cheapest first

1. **Named-libc calls instead of `syscall(nr)`.** A `lib/rtl/platform/libc/`
   backend declaring `external` libc symbols (`read`, `write`, `open`, ...) —
   ordinary Pascal, proven to work today, no compiler change. The compiler's
   ~9 direct kinds map Linux-nr → named import in the thunk (a small table).
   *Small.*
2. **Per-OS constants — the hidden bulk.** errno (`EAGAIN` 35 vs 11), open
   flags (`O_CREAT` 0x200 vs 0x40), mmap (`MAP_ANON` 0x1000 vs 0x20), signal
   numbers, ioctl/termios codes — all hard-coded Linux in `lib/rtl` and the
   `lib/crtl` headers. One constants unit/header per OS, **generated from the
   system headers on the VM**, not hand-typed. *Medium; reused by every libc OS.*
3. **Struct layouts.** `stat` (no `statx`), `dirent`, `termios`, `sigaction`,
   `sigset_t`, `sockaddr` with `sa_len`. Also generated. *Medium.*
4. **Linux-only facilities → OS model.** epoll/timerfd → kqueue (or `poll`
   fallback); futex → libc pthread mutex/cond; getrandom → `arc4random`;
   prlimit/socketcall/set_thread_area → plain libc or drop. Confined to
   scheduler/sockets/thread units; **single-threaded first**. *Medium.*
5. **The four raw entries.**
   - `rt_sigreturn` → install handlers via libc `sigaction`; libc's
     trampoline does the return.
   - `clone` / thread `exit` → `pthread_create` (`palpthread.pas` exists).
   - `arch_prctl` (GS TLS) → **open question**: can OpenBSD userland set the
     GS base at all? If not, TLS model needs a libc-owned path. Phase 2.
   - This resolves the pinsyscalls decide as its option (b).

## OpenBSD-specific risks (not in any earlier ticket)

- **xonly (7.3+, amd64):** text pages are execute-only, not readable. pxx
  writes section-less ELFs; any constant, string or jump table read from the
  RX segment faults. **Spike this first** — it is the only item that could
  force an ELF layout change.
- **IBT/BTCFI (7.4+):** indirect-branch targets need `endbr64` on capable
  CPUs. Escape hatch `PT_OPENBSD_NOBTCFI`; qemu without IBT will not show it,
  so do not read a green VM run as compliance.
- **ELF identity:** `.note.openbsd.ident`, interp `/usr/libexec/ld.so`,
  `DT_NEEDED libc.so.<maj>.<min>`.

## Order of work

0. **Infra.** OpenBSD amd64 VM under qemu/KVM on plexus. **All images and
   disks under `/data`** (root is 99% full as of 2026-11-12 — 2.4G free).
   Runner script: copy binary in, run, capture stdout + exit code.
1. **xonly spike.** Hand-built pxx hello-world (`--rtl-libc`, interp + note
   patched) on the VM. Does it load, does it read its own rodata?
2. **libc backend, single-threaded** (items 1 + 5a + ELF identity) →
   hello-world, then the scalar + heap/string/exception torture from
   `feature-port-openbsd-libc`, byte-identical output.
3. **Constants + structs generated** (items 2, 3) → file I/O, dirs,
   termios. Closes `feature-port-openbsd-libc`.
4. **Facilities** (item 4) and **threads/TLS** (5b, 5c).
5. **NetBSD** — second constants/struct table. **Minix 3** — NetBSD-derived
   libc, narrower; note it has had no release since ~2017 (3.4.0rc6).

## Acceptance

- Linux default build **bit-identical** (self-host fixedpoint untouched);
  everything new behind the platform switch.
- Per OS: torture program output byte-identical to Linux; kernel-entry count
  from `tools/syscall_scan.py` (never `objdump -d`) stated as
  **pinsyscalls compliance** for OpenBSD, not "zero".
- Hosted milestone (the umbrella's real goal): pxx compiles itself on the VM.

## Related

`feature-port-openbsd-libc`, `decide-openbsd-pinsyscalls-vs-the-rt-sigreturn-residual`,
`feature-rtl-libc-frontend-sites-and-thread-errno`, `feature-port-freebsd-native`,
`umbrella-pxx-hosted-beyond-linux`, `devdocs/dev/portability-axes.md`.

## Log

- 2026-11-12 — filed and claimed (pxx2 session). Plan agreed with owner.
- 2026-11-12 — **`--rtl-libc` was broken on master and nothing noticed.**
  Hello-world SIGSEGV on the first `WriteLn`, both pinned v455 and HEAD
  `30386bbbce`. Cause: the DCE compaction (`dce.inc`) remaps every code-position
  table except `LibcSyscallCallPos`, and `EmitLibcSyscallThunk` patches after
  DCE. Measured: 30 recorded sites up to offset 32205 in a 15984-byte image;
  17 live `e8 00000000` left, each falling through into the next routine, while
  the stale patches wrote rel32s into unrelated code. Fixed by remapping the
  table in `dce.inc`. Regression: `test/test_rtl_libc_torture.pas` in
  `test-core` (raw vs libc output identical, `syscall_scan` = 1); it crashes
  (SIGILL) on the pinned compiler and passes on the fix. Self-host converges,
  `tools/gate.sh quick` green.
- 2026-11-12 — ELF layout note for the xonly spike: x86-64 already emits a
  separate `R` PT_LOAD for rodata/string literals (good), but the ELF header and
  program headers sit at the start of the `R E` segment, so an xonly loader
  that reads phdrs from memory would fault. Check on the VM.
- 2026-11-12 — VM infra: OpenBSD 8.0 amd64 under qemu/KVM in `/data/vm/openbsd`
  (`install.py` = unattended autoinstall over serial; the stock ISO is used
  as-is — remastering it with xorriso moves `cdboot` and `cdbr` can no longer
  find it).
- 2026-11-12 — **Spike result: a libc-free pxx binary runs on OpenBSD 8.0.**
  Measured on the VM (OpenBSD 8.0 GENERIC.MP amd64, libc.so.104.0):
  - A plain Linux pxx ELF is ENOEXEC (no ident note); the shell then tries it
    as a script ("NUL byte unexpected").
  - libc.so.104.0 exports neither `syscall` nor `__syscall` -- confirmed, so
    today's `--rtl-libc` cannot work there.
  - Hand-patched `--os=freebsd` hello-world: FreeBSD ABI note renamed to
    `OpenBSD\0` (same 8-byte name, type 1, desc set to 0) -> exec accepted;
    then SEGV_ACCERR at the first `call`, because the FreeBSD entry's
    `mov rsp, rdi` does not apply (OpenBSD starts with argc at [rsp], like
    Linux). NOP'd -> runs until the first syscall made from pxx's code:
    `PINS getrlimit, addr 4003b7` + SIGABRT. Pinsyscalls IS enforced for a
    static binary.
  - Added a `PT_OPENBSD_SYSCALLS` (0x65a3dbe9) table of
    {u32 vaddr, u32 sysno} pairs at the end of the file (GNU_STACK phdr
    reused): every number 1..330 pinned to the ONE generic syscall site,
    direct sites pinned to their own number -> **"hello from pxx", exit 0**,
    with the base system's execute-only text in force (`/bin/ls` maps its
    text `E` only).
  - Loader rules, from sys/kern/exec_elf.c (elf_read_pintable): the whole
    table is DISCARDED if any entry has sysno <= 0 or >= SYS_MAXSYSCALL (331
    on 8.0) or an offset past the text end, or if it is larger than
    SYS_MAXSYSCALL*2 entries; a number listed twice becomes "allowed
    anywhere"; offsets are vaddrs for ET_EXEC (exe_base 0); the table is
    read only when there is no PT_INTERP.
  - **Consequence for the plan:** OpenBSD can be a raw-syscall port like
    FreeBSD -- an OpenBSD translator (numbers/structs/errno) behind the one
    syscall site, the ident note, a pin table from the ELF writer, no
    FreeBSD entry fixup. No libc, no PLT, no ld.so. Cost: syscall numbers are
    not a stable ABI on OpenBSD, so binaries would be tied to a release, as
    the base system's own static binaries are. (The libc route is tied too:
    a libc major bump also breaks old binaries without compat libs.)
    Owner decision needed: raw-syscall OpenBSD vs the libc route in this
    ticket. NetBSD/Minix keep their stable syscall tables either way.
  - Still open: does pxx ever READ its own text (jump tables, constants
    placed in code)? Hello-world reads only the R segment. IBT/BTCFI not
    tested (needs a CPU with IBT; qemu without it proves nothing).
  - Spike scripts (not committed): note rename + entry NOP + pin table
    builder, each ~40 lines of Python; recipe above is enough to redo them.

### 2026-11-12, later: `--os=openbsd` built as an EXPERIMENTAL direct-syscall target

The spike result has been turned into a compiler option. It is additive and
can be reverted. The owner's earlier ruling ("OpenBSD goes the libc route")
still stands until they confirm the direct route. Doing it this way made the
FreeBSD sites generic (`KernelTranslated`, `KernelAbiUnit`, `KernelAbiProc`,
`TlsSegPrefix` in defs.inc), and that work is needed whichever route wins.

- The translator is `compiler/builtin/obsdabi.pas` (phase 1): files,
  directories, memory (brk emulated), time, process basics, TLS via
  `__set_tcb` with fs-prefixed accesses, uname, rlimits,
  `/proc/self/environ` and `/proc/self/exe`.
- The ELF writer adds the OpenBSD ident note and a `PT_OPENBSD_SYSCALLS`
  table that pins numbers 1..330 to the one `syscall` in `ObRawA`.
- Refused for now: `--threadsafe`, `-g`, plus FreeBSD's refusals.
- Verified: hello world and a file/directory/environment/time program give
  output identical to Linux on OpenBSD 8.0. Linux, FreeBSD, aarch64, arm32,
  i386, `--threadsafe` and `-g` binaries are byte-identical to a control
  compiler built at the parent commit.
- Next: signals (sigaction, 16 B struct, SA_SIGINFO 0x40; the
  siginfo/ucontext layouts still need measuring), then threads (`__tfork`),
  then sockets.

### 2026-11-12: `--os=openbsd` signals

Signals are done the way fbsdabi does them, in `ObSigEntry`/`ObRtSigaction`.
Also handled: rt_sigprocmask, rt_sigpending, rt_sigsuspend, pause,
sigaltstack, tkill/tgkill (via thrkill), getitimer/setitimer and alarm.
Things measured on 8.0:

- `struct sigcontext` is the handler's third argument. Its fields:
  rdi@0 … rax@112, trapno@152, err@160, rip@168, rflags@184, rsp@192,
  fpstate@208, mask@220, cookie@224.
- siginfo is laid out signo@0, code@4, errno@8, then pid/addr@16.
- sigset_t is a u32. sigprocmask takes the mask by value and returns the
  old mask in rax.
- OpenBSD kills a syscall made while rsp is outside a MAP_STACK region, so
  pxx's BSS alt stack is never handed to it. The translator registers its
  own 64 KiB MAP_STACK region.
- An SSE trap arrives as FPE_FLTINV with trapno 0. The real cause is
  re-derived from fx_mxcsr (at fpstate+24), the way Linux does it.

Six signal tests and an `--fpc-mem-errors` nil write match Linux byte for
byte. Next: threads (`__tfork`, and thread stacks need MAP_STACK too), then
sockets.

### 2026-11-12: `--os=openbsd` threads

`--threadsafe` is no longer refused. How each part works:

- **Creation.** The clone stub (thread_emit.inc) has an OpenBSD leg that
  calls clone through the thunk, with the child's resume address in r9. The
  translator turns that into `__tfork`, via `ObTforkA`. The pin table pins
  SYS___tfork (8) to `ObTforkA`'s syscall instruction, and every other number
  to `ObRawA`'s.
- **Exit.** The thread takes a spin lock and switches to a shared MAP_STACK
  exit stack. It clears ctid, wakes both futex queues (calling ObRawA by
  address), then calls `__threxit(&lock)`, so the kernel releases the lock.
  The ctid pointer is parked in TLS slot 14, as on FreeBSD.
- **Stacks.** A thread or coroutine stack must be MAP_STACK. The new
  `PXX_OS_OPENBSD` define makes palthread and scheduler pass Linux MAP_STACK.
- **sigaltstack.** It now passes the program's buffer straight through,
  because the kernel converts the region itself (measured).
- **Assembler limits found.** pxx's asm has no `jmp reg` or `call reg`, so
  the code uses `push reg; ret` and a `call label` trampoline.

Results:

- Eleven thread tests match Linux, and `lib_fpc_thread_surface` passed 40
  runs out of 40.
- Linux, FreeBSD, aarch64 and i386 `--threadsafe` binaries are
  byte-identical to a control built at the parent commit.
- `test_a_joined_thread_leaves_the_pal_reap_table` reads `/proc/self/maps`,
  which OpenBSD does not have.

Next: sockets.

### 2026-11-12: `--os=openbsd` sockets, ppoll/pselect6, epoll

- **Sockets.** fbsdabi's socket section was ported with OpenBSD's numbers,
  measured on 8.0: AF_INET6 24, SOCK_NONBLOCK $4000, SOCK_CLOEXEC $8000,
  MSG_NOSIGNAL $400, MSG_CMSG_CLOEXEC $800, accept4 93, SO_PEERCRED $1022
  (fields reordered). OpenBSD has no SO_DOMAIN, SO_PROTOCOL or TCP_KEEP*.
  msghdr, cmsghdr and sockaddr are the same as FreeBSD's.
- **ppoll and pselect6** (109/110) take a u32 mask by pointer. pxx's PalPoll
  uses ppoll, so before this every connect-with-timeout failed with ENOSYS.
- **epoll** runs over kqueue (269/72). kevent is 32 bytes, with FreeBSD's
  offsets.
- **Results.** Nine socket tests match Linux. `lib_net_v6only` cannot: OpenBSD
  IPv6 sockets are always v6-only.

Next: termios, eventfd/timerfd (OpenBSD has neither natively), and /proc.

### 2026-11-12: `--os=openbsd` termios

- fbsdabi's termios tables and tty ioctls were ported. Differences measured
  on 8.0: no IUTF8, OCRNL/ONOCR/ONLRET $10/$40/$80, CRTSCTS $10000. The
  c_cc indices and ioctl numbers are FreeBSD's.
- MapBits now skips a 0 source entry. Without that, "no counterpart"
  (IUTF8) would match every value.
- `c_os_freebsd_termios` matches Linux on a real tty (ssh -tt).
- Still open:
  - ptys: OpenBSD has /dev/ptm with PTMGET instead of /dev/ptmx, and its
    slaves are /dev/ttypN, not /dev/pts/N.
  - eventfd and timerfd: OpenBSD has neither; they would need emulating
    with a pipe or kqueue EVFILT_TIMER.
  - /proc/self/maps.

### 2026-11-12: `--os=openbsd` gap sweep; `make test-openbsd`

I ran test-freebsd's whole list against OpenBSD and fixed every difference
that could be fixed:

- **timerfd** over a kqueue with one EVFILT_TIMER (NOTE_NSECONDS). Without
  it, CoSleep registered -ENOSYS as an fd and hung.
- **Wait statuses.** Signal numbers are mapped back; WCONTINUED is 8 on both.
- **rt_sigtimedwait** via __thrsigdivert, with the mask passed by value.
- **futimens.** utimensat with a nil path.
- **New mappings:** statfs/fstatfs (568-byte struct, measured), times,
  setre*/setres*/getres*, get/setgroups, mlock*, sync, clock_settime,
  utimes, mknod(at), set_tid_address and unshare(0).
- **prctl** names via setthrname/getthrname.
- **sched_*** answered as Linux does for SCHED_OTHER. sched_getaffinity
  reports hw.ncpuonline CPUs.
- **fallocate** mode 0 grows the file with ftruncate.
- **Paths:** /dev/full (/dev/zero with writes failing ENOSPC),
  /proc/sys/kernel/hostname, and readlink /proc/self/fd/N for directory
  fds (fchdir in, getcwd, fchdir back).
- **tools/vm/openbsd.sh run** passes PXX_TEST_* through, uses an 8 MB stack
  ulimit, and runs on a real tty with PXX_VM_PTY=1 (ssh -tt inside a local
  script(1)).
- **`make test-openbsd`** checks about 90 programs for byte-identical output
  and exit code against Linux.

Left out of the target, because OpenBSD cannot do them:

- lib_net_v6only (no dual-stack IPv6).
- test_a_joined_thread_leaves_the_pal_reap_table (/proc/self/maps).
- test_thread_clone (raw stack without MAP_STACK).

Hazard found: a test opening /dev/full for writing as root on OpenBSD
created a regular file there. It was removed, and the translator now
intercepts that path.

### 2026-11-12: `--os=openbsd` ptys

- /dev/ptmx is emulated with /dev/ptm and PTMGET (0x40287401; struct ptmget
  is 40 bytes: cfd, sfd, cn[16], sn[16]). The master is kept and the slave
  closed.
- TIOCGPTN answers the master's minor (st_rdev at offset 28; masters are
  major 6, slaves major 5). Anything else gives ENOTTY, as on Linux.
- /dev/pts/N opens /dev/tty + "pqrstuvwxyzPQRST"[N div 62] +
  "0-9a-zA-Z"[N mod 62]. Measured on 8.0 with PTMGET in a loop: minor 61 is
  ttypZ, and the 63rd PTMGET fails with ENOENT, because the stock /dev has no
  ttyq*.
- TIOCSPTLCK succeeds on a master: OpenBSD ptys have no lock.
- c_pty_family, cisatty and lib_termio_isatty match Linux and are now in
  `make test-openbsd`.

### 2026-11-12: `--os=openbsd -g`

- The refusal is gone. The debug sections now start after the pin table
  (file offset past the data plus (OB_SYS_MAXSYSCALL-1)*8) in both 64-bit
  writeELF variants, instead of on top of it.
- Checked: readelf reads the line and info sections cleanly; fileio,
  test_nilpy_local_named_like_a_class and test_stack_overflow_raise built
  with -g give the same output on OpenBSD as on Linux; every other target
  (Linux, FreeBSD, aarch64, arm32, i386, with and without -g, --threadsafe)
  is byte-identical to a control compiler.

### 2026-11-12: `--os=netbsd` (experimental), single-threaded

- VM: NetBSD-11.1-amd64-live.img (sha512 checked) under /data/vm/netbsd,
  booted with OVMF. Its EFI partition got /EFI/NetBSD/boot.cfg with
  consdev=com0 (mtools, before the first boot), so the console is on serial
  with no keystrokes; then root login on the serial console set up sshd,
  dhcpcd and a root key. The live image grows its root to the disk (8 GB).
  Typing at the efiboot menu was unreliable: `consdev com0` redraws the menu
  and the next key was taken as "boot default". tools/vm/netbsd.sh, port 2227.
- Probed on the VM with offsetof() and the headers (copied to the
  scratchpad): errno, open/AT/mmap flags, clocks, signals and SA_ flags,
  siginfo/ucontext/mcontext (_REG_* order), stat (152 B), dirent, statvfs
  (3296 B), termios (FreeBSD's except CRTSCTS $10000 and no IUTF8), ioctls
  (FreeBSD's), sockets (AF_INET6 24, MSG_NOSIGNAL $400, SO_RCVTIMEO $100C,
  TCP_KEEPIDLE 3), poll bits, TFD/EFD flags (EFD_SEMAPHORE 2), futex ops
  (Linux's).
- epoll: the syscalls exist (502..504) but no header is installed. Measured
  with a pipe: the kernel's epoll_event is 16 bytes, data at 8;
  EPOLL_CLOEXEC is O_CLOEXEC ($400000), Linux's $80000 is EINVAL.
- PAD arguments: mmap's offset is the 7th argument, read from [rsp+8]. NbRawA
  pushes a 7th word (and a fake return slot) on every call, and captures CF
  before restoring rsp.
- TLS in fs via _lwp_setprivate (TlsSegPrefix $64, as OpenBSD), because
  setcontext restores the fs base from _mc_tlsbase.
- O_NOFOLLOW on a symlink fails with EFTYPE (79) on NetBSD; mapped to ELOOP.
- `make test-netbsd`: test-openbsd's lists without threads, plus
  lib_net_v6only (dual-stack works here). All match Linux. Every other target
  is byte-identical to a control compiler (C programs built with -g differ
  only in the crtl source path inside the debug info, because the control
  reads crtl from its own tree; stripped, they are identical).
- Threads (same day): the stub's OpenBSD leg (clone through the thunk, child
  entry in r9) serves NetBSD too. NbClone: getcontext (selectors, mask, FPU),
  rip = child entry, rsp = stage, _mc_tlsbase = the TLS block with
  _UC_TLSBASE, _lwp_create(LWP_DETACHED). Exit of a non-main LWP (main is
  always LWP 1): wait for the parent's tid store, block all signals, then a
  register-only routine clears the word, wakes both futex queues and
  _lwp_exits, with rsp moved to a shared read-only area because __futex's
  7th argument is read from [rsp+8]. The thread list of test-openbsd plus
  test_thread_clone all match Linux; lib_fpc_thread_surface and
  test_parallel_for_private ran 60 times each with no failure.

### 2026-11-13: `--os=netbsd --target=aarch64`

- VM: NetBSD-11.1 evbarm-aarch64 gzimg/arm64.img (sha512 checked) as
  /data/vm/netbsd-arm64/nb.qcow2, AAVMF, qemu TCG, port 2229, set up over the
  serial console (root key; sshd is already on in this image). Its root comes
  up noatime from somewhere other than /etc/fstab: tools/vm/netbsd.sh start
  remounts it with atime (c_crtl_utimensat read back "now" otherwise, for
  native code too).
- Measured: svc's immediate is the syscall number; svc 0 is SYS_syscall with
  the number in x17 (C carry = error, as on amd64). __sigtramp_siginfo_2 is
  `mov x0, x28; svc SYS_setcontext`. ucontext 944 B: sigmask at 16,
  mcontext at 64 = __gregs[35] (x0..x30, sp, pc, spsr, tpidr), Linux's order.
- The arm64 front moved out of fbsdabi into compiler/builtin/lxa64front.inc
  (LxA64Front calling the unit's LxX64Call); non-fork clones go to the x86
  dispatch's clone with ctid/tls swapped back and a5 (the child entry) kept.
- nbsdabi under CPU_AARCH64: NbRawA/NbSigTramp/NbClearTidExitA in aarch64
  assembler (no stack move: __futex's 7th argument is x6), NbSigEntry builds
  Linux's arm64 ucontext, NbClone sets _REG_PC/_REG_SP/_REG_X0/_REG_TPIDR.
  PXXNbsdSyscall reports the main thread's tpidr_el0 once with
  _lwp_setprivate. PathIs/MapBits take pointer + count, as in fbsdabi.
- Compiler: the aarch64 clone stub's NetBSD leg calls Linux clone through
  the thunk (EmitSvcA64Leaf) with the child entry in x5, after copying the
  parent's init-image slot into the new block.
- make test-netbsd-arm64: test-netbsd's lists minus test_float_exception_mask,
  test_signal_num_threads_race, test_signal_threads, test_thread_clone (x86-64
  only) and lib_sockets (qemu-user's errno). All match.
  lib_fpc_thread_surface and test_parallel_for_private ran 40 times each with
  no failure.

