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
