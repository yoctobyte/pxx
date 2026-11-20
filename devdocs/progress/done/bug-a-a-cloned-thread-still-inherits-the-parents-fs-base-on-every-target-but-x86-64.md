---
slug: bug-a-a-cloned-thread-still-inherits-the-parents-fs-base-on-every-target-but-x86-64
title: a cloned thread still inherits the parent's fs base on every target but x86-64
summary: >
  The residual half of
  bug-a-a-pxx-created-thread-shares-glibc-s-thread-pointer-so-two-threads-share-one-malloc-state,
  which was fixed on x86-64 only. `PXX_CLONE_THREAD` still omits `CLONE_SETTLS`
  and `PthreadRouteAvailable` in `lib/rtl/palthread.pas` is `{$ifdef CPUX86_64}`,
  so i386, aarch64, arm32 and riscv32 still hand a cloned thread the parent's
  thread-pointer base. A program on those targets that links a shared library
  and allocates through a C library on more than one thread corrupts glibc's
  heap, exactly as x86-64 did. The compiler's whole-program warning still fires
  there, so the hazard is at least announced. NOT MEASURED on any of those
  targets -- this is the x86-64 mechanism carried across by reading the source,
  and the first job is to reproduce it, starting with i386, which builds AND
  runs on this box.
track: A
type: bug
prio: 45
owner: rd
status: done
blocked-by: []
---

## What is already done

x86-64 routes thread creation through `pthread_create` when it resolves (an
optional import, `weakexternal`), so glibc makes the thread and owns its `fs`.
`PxxPthreadStart` installs pxx's own `gs` block and alt stack in the child, so
pxx's own thread-locals are unaffected. See the 2026-09-14 section of
`devdocs/dev/threading.md`.

## What is left

`PthreadRouteAvailable` returns False off x86-64 because `PxxPthreadStart` uses
`arch_prctl(ARCH_SET_GS)`, which is x86-64's way of installing a thread block.
Each other target needs its own equivalent in the trampoline — the same one its
`__pxxclone` child leg already uses — and then the route opens with no other
change: the weak imports, the handle fields, the create/join dispatch and the
DT_NEEDED collapse are all target-independent.

**Start by reproducing, not by porting.** `test/thread_glibc_malloc_two_threads.pas`
is the repro and i386 is the cheap target: it builds and runs here. A null
result there is information — it would mean the hazard needs something i386's
libc does differently, and that is worth knowing before four ports.

## Why it is prio 45 and not 85

The x86-64 instance was ranked 85 because it aborted the lekkerzeilen demo, on
the host everybody develops on. These targets have no demo standing on them and
a cross-built program linking a shared library is rare. It is the same defect and
a smaller blast radius — rank the reach, not the mechanism.

## Closed 2026-11-20 (rd): already fixed, the ticket was left open

0ed2b7f6e1 (2026-09-27, "fix(A): pxx threads on i386, aarch64 and arm32 no
longer share glibc's thread pointer") opened the pthread route on all three
targets. lib/rtl/palthread.pas defines PXX_PTHREAD_ROUTE for CPUX86_64,
CPUI386, CPUAARCH64 and CPUARM. That commit added the test-threads rows for
test/thread_glibc_malloc_two_threads.pas on i386, aarch64 and arm32, beside
the x86-64 one (Makefile, the test_tglibc2_* rows).

Re-measured at 62ae6a37cd: the repro survives on i386, aarch64 and arm32, 3
runs of 3 each. Before that commit it aborted 1/3, 2/3 and 3/3 of runs. The
test-threads run for the alt-stack change (the same day) was 0 failures,
these rows included. riscv32 has no threads (the --threadsafe gate), so it
is out of scope rather than open.
