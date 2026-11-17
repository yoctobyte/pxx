---
track: ESP
tags: [xtensa, rtl, pal, syscalls, busybox, gibux]
prio: 10
type: bug
blocked-by: []
summary: "The hosted (posix) PAL backend answered PAL_ERR_UNSUPPORTED on xtensa, without issuing a syscall, for 19 calls: uname, times, prlimit64 (getrlimit/setrlimit), getrusage, setsid, getsid, setpgid, getpgid, getgroups, setgroups, getpriority, setpriority, sethostname, alarm (setitimer), rt_sigprocmask, rt_sigtimedwait, utimensat, fdatasync and sync. The stated reason was an unmeasured syscall table. On Gibux, BusyBox `uname -a` printed garbage and then hit StoreProhibited. The numbers now come from Linux 6.18's arch/xtensa/kernel/syscalls/syscall.tbl (rt_sigtimedwait is the time64 421, utimensat was already 412), and each one is confirmed by name under qemu-xtensa -strace."
status: done
owner: unassigned
---

# The xtensa PAL refused 19 syscalls it had numbers for

pxx2 reported it from BusyBox on Gibux. Repro: /data/tmp/pxxprog/un.c printed `uname rc -1 sizeof 390` with every field empty, and no syscall appeared in Gibux's trace=all or under qemu-user.

## Fix
lib/rtl/platform/posix/platform_backend.pas:
- the xtensa constant block gains fdatasync 27, sync 178, setsid 128, getgroups 196, getpriority 132, setpriority 133, getsid 129, setpgid 148, getpgid 149, setitimer 134, sethostname 198, setgroups 197, rt_sigtimedwait 421 (time64, because TPalTimeWord is Int64 there), rt_sigprocmask 227, times 154, uname 208, prlimit64 330 and getrusage 190;
- the 19 `{$ifdef CPU_XTENSA} PAL_ERR_UNSUPPORTED` arms are removed.

xtensa has no alarm syscall. alarm already goes through setitimer on every target, using native-word timevals, which is right for xtensa.

## Test
tools/check_xtensa_pal_syscalls.py runs test/c_xtensa_pal_syscalls.c on x86-64 and under qemu-xtensa. Both must print gcc's output (test/c_xtensa_pal_syscalls.expected), and the xtensa strace must name all 14 syscalls the program reaches. The previous runtime prints `uname -1 sysname  nodename-set 0` and fails the rest.

The first version of the test disagreed between x86-64 and xtensa on three lines. That was its own unspecified argument evaluation order (gcc and pxx-x86-64 read `u.nodename` before calling `uname`), not a runtime bug. The calls are now sequenced before their results are read.
