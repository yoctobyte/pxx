# bug: hosted C on wasm32 stopped building -- crtl named SYS_* numbers wasm32 does not have

Found 2026-11-19 by frank-user (dupwt); fixed in the crtl lane the same day.

b3c5f711ea (toybox surface, 2026-11-14) added raw `syscall(SYS_x, ...)` calls
to crtl with no guard. `<sys/syscall.h>` deliberately names no numbers on
wasm32, so every hosted C program for wasm32 failed with
`fcntl.c:56: undeclared identifier 'SYS_openat'`. That includes
test/c_wasm32_hosted_stdio.c and test/c_wasm32_math_h.c.

Fix: 24 call sites in fcntl.c, sys/{eventfd,mman,resource,stat,statfs,sysinfo}.c
and unistd.c now follow the header's convention:
`#ifdef SYS_x ... #else errno = ENOSYS; return -1; #endif`.
Some sites differ:
- getentropy wraps its whole loop.
- sysconf(_SC_NPROCESSORS_*) answers 1 CPU.
- sysconf(_SC_ARG_MAX) falls back to 128 KiB.

Other targets compile exactly the code they did before.

Sites that were already safe and were left alone:
- netinet/in.c, under `__CRTL_RAW_SOCKADDR`, which requires the SYS_ names.
- posix_fadvise and fallocate, which are guarded per architecture.

Result: c_wasm32_hosted_stdio matches gcc again.

c_wasm32_math_h still differs: `isnan(NAN)` gives 0. That is a separate bug
from the same commit. On wasm32, C file-scope initialisers never run once they
moved into `__pxx_c_main_init` (CEmitMainInitProc); git bisect run names
b3c5f711ea. It was handed to frank-user, whose commit it is.

Follow-up: frank-user fixed the initialiser bug in dc9ad070c3. All three C
wasm32 rows (hosted_stdio, math_h, variadic) match gcc there.
