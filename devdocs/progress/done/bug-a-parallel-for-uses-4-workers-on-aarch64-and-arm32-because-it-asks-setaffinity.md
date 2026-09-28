---
track: A
prio: 55
type: bug
blocked-by: []
status: done
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "lib/rtl/palparallel.pas used 122 (aarch64) and 241 (arm32) for sched_getaffinity; those are sched_SETaffinity. The call failed with EINVAL and `parallel for` fell back to 4 workers on every aarch64 and arm32 machine, hardware included. getaffinity is 123 and 242."
owner: ""
---

# parallel for uses 4 workers on aarch64 and arm32, because it asks setaffinity

```pascal
uses palparallel;
begin WriteLn(PXXParForWorkers) end.
```

On a 12-CPU box: x86-64 and i386 print 12, aarch64 and arm32 print 4. A
teammate saw it with QEMU_STRACE: `sched_setaffinity(...) = -1 EINVAL`, the
wrong call.

## Fix

In `lib/rtl/palparallel.pas`, `SYS_sched_getaffinity` is now 123 on aarch64
(the generic table) and 242 on arm32 EABI. i386 (242) and x86-64 (204) were
already right.

## Test

`test/test_parallel_for_worker_count_follows_the_cpu_affinity.pas` in
`test-threads`: i386, aarch64 and arm32 must print what x86-64 prints. The
unit from one commit back prints 4 on aarch64 and arm32. The row cannot fail
on a 4-CPU box.
