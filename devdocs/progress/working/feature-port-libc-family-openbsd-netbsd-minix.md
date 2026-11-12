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
