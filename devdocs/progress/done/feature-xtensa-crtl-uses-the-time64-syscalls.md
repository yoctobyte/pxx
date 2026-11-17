---
track: ESP
tags: [crtl, rtl, xtensa, syscalls, time64, gibux]
prio: 30
type: feature
blocked-by: []
summary: "On xtensa, the runtime (PAL, scheduler, palfutex) and crtl now issue the *_time64 syscalls with a 64-bit __kernel_timespec, as riscv32 always has: clock_gettime64 403, clock_settime64 404, clock_nanosleep_time64 407, timerfd_settime64 411, utimensat_time64 412, pselect6_time64 413, ppoll_time64 414, futex_time64 422. Gibux on the ESP32-S3 implements that word-size-independent set; qemu-xtensa implements it too. crtl's xtensa table gains the time64 rows that the qemu sweep could not name, taken from Linux v6.12 syscall.tbl via Gibux's asm/unistd.h."
status: done
owner: unassigned
---

# crtl on xtensa uses the time64 syscalls

The Gibux kernel session asked for this. Gibux keeps its user structures in fixed 64-bit types, so the cheapest correct ABI is the calls whose structures do not depend on word size.

## What changed
- **platform_backend.pas:** PAL_TIME64 is now defined for xtensa too. The xtensa numbers are 403 (clock_gettime), 404 (clock_settime, previously refused on xtensa), 407 (clock_nanosleep), 412 (utimensat) and 414 (ppoll).
- **scheduler.pas:** SCHED_TIME64 is defined for xtensa, and timerfd_settime is 411. The old note said xtensa was not time64 because "410, the settime64 number, is Unknown syscall". But 410 is timerfd_GETtime64, and both 410 and 411 answer under today's qemu.
- **palfutex.pas:** futex_time64 (422) with a 64-bit timespec.
- **crtl:**
  - select.c uses pselect6_time64 on xtensa.
  - poll.c's ppoll uses ppoll_time64 with a 64-bit timespec on riscv32 and xtensa.
  - unistd.c's pause uses ppoll_time64 on xtensa.
  - sys/syscall.h's xtensa arm gains rows 404–421. Each row was checked against Gibux's header.

crtl's own time_t stays `long` (32-bit). Only the kernel-facing structures are 64-bit. A 64-bit time_t for xtensa user code, as musl does it, would be a separate and larger change.

## Test
tools/check_xtensa_time64_syscalls.py runs test/c_xtensa_time64_syscalls.c under `qemu-xtensa -strace`:
- The program prints "time64 ok": the clock advanced across a 2 ms sleep.
- The trace names no time32 call. The old compiler issues clock_gettime, nanosleep, ppoll and pselect6.

`make test-xtensa` passes as well.

## The syscalls the runtime issues on xtensa (2026-11-17)
Pascal runtime (platform_backend, scheduler, palfutex):
> close 9, read 12, write 13, lseek 15, epoll_wait 18, epoll_ctl 19, truncate 22, ftruncate 23, fsync 26, chdir 41, getcwd 43, fchmod 52, fchown 53, umask 58, getdents64 60, ioctl 66, fcntl 67, mmap2 80, munmap 81, mprotect 82, socket 96, setsockopt 97, getsockopt 98, shutdown 99, bind 100, connect 101, listen 102, getsockname 104, getpeername 105, sendto 110, recvfrom 111, clone 116, execve 117, exit 118, exit_group 119, getpid 120, wait4 121, kill 123, gettid 127, getuid 137, getgid 139, geteuid 140, getegid 141, getppid 150, rt_sigaction 226, epoll_create1 275, openat 288, mkdirat 289, mknodat 290, unlinkat 291, renameat 292, linkat 293, symlinkat 294, readlinkat 295, fchownat 297, fchmodat 300, faccessat 301, dup3 310, pipe2 311, timerfd_create 312, accept4 333, getrandom 338, statx 351, clock_gettime64 403, clock_settime64 404, clock_nanosleep_time64 407, timerfd_settime64 411, utimensat_time64 412, ppoll_time64 414, futex_time64 422

crtl's C wrappers add the calls below, each issued only when a program uses that wrapper. Some sit in another architecture's `#if` branch, so this is a superset:
> readv, writev, pread64, pwrite64, flock, fallocate, fadvise64_64, the xattr family, mlock/munlock(all), mremap, msync, madvise, shm*, sem*, msg*, sendmsg, recvmsg, socketpair, tgkill, prctl, personality, setitimer, getitimer, acct, sched_*, capget/capset, mount, umount2, swapon/off, chroot, pivot_root, statfs(64), fstatfs(64), adjtimex, syslog, reboot, sysinfo, unshare, inotify*, setns, eventfd2, preadv, pwritev, prlimit64, renameat2, execveat, faccessat2, pselect6_time64, ppoll_time64

## Compared with Gibux's wishes
- **lseek and fcntl:** the runtime uses plain lseek 15 and fcntl 67, not _llseek 17 and fcntl64 61. Both are real Linux xtensa calls, and off_t is 32-bit here.
- **Fork:** fork is clone(SIGCHLD) (PalBackendFork, and the spawn helper), not vfork. A no-MMU kernel needs a vfork path.
- **rt_sigaction:** it is only used for SIG_IGN. The all-zero 4×Int64 block reads correctly as the generic {handler, flags, restorer, mask64} struct.
- **itimers:** setitimer and getitimer pass a word-sized timeval.
