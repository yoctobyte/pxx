---
slug: bug-c-the-shared-runtime-leaves-out-four-crtl-headers
track: C
prio: 60
type: bug
status: done
owner: pxx2
created: 2026-11-25
closed: 2026-11-25
found-by: pxx2 (linking Path B's Xorg with --shared-runtime)
tags: [crtl, shared-runtime, link]
summary: "A --shared-runtime program calling backtrace failed to link with `undefined reference to 'backtrace'`, although crtl defines it. The runtime object is crtl's <pxx/runtime_all.h>, which must include every header that has a src/<name>.c; execinfo.h, semaphore.h, threads.h and sys/ptrace.h were added to crtl after it and never listed. The checker its comment named (tools/check_runtime_all.py) did not exist. All four are listed now (semaphore and threads under __PXXRT_THREADSAFE, with pthread), and `tools/gen_crtl_map.py --check`, already a gate step, fails when one is missing. Also new in crtl, for Xorg: <sys/epoll.h> (struct epoll_event packed on x86-64 only, as the kernel's; epoll_create and epoll_wait fall back to epoll_create1 and epoll_pwait where the older calls are missing) and <sys/io.h> (iopl, ioperm; ENOSYS off x86). Before this, Xorg's os/ospoll.c and lnx_video.c compiled against the host's glibc headers. Test c_xgaps26 and c_xgaps26_sr against gcc."
---

# The shared runtime leaves out four crtl headers

`pxx --link` adds one runtime object to `--shared-runtime` objects, built
from `lib/crtl/include/pxx/runtime_all.h`. Including a crtl header pulls in
its implementation, so a header that is missing from that list means its
functions are missing from every shared-runtime program. A self-contained
object is not affected, because it pulls the implementation in when it
includes the header.

Xorg's `os/backtrace.c` calls `backtrace`. libdrm and the rest of Path B
are compiled with `--shared-runtime`, and the Xorg link stopped on:

```
pascal26 --link: undefined reference to 'backtrace'
```

`gen_crtl_map.py --check` now lists every `src/<name>.c` that has a
header and fails if `runtime_all.h` does not include it.
