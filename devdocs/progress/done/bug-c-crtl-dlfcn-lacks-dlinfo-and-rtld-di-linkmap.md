---
track: C
tags: [crtl, dlfcn, rump, system-libs]
prio: 70
type: bug
blocked-by: []
summary: "crtl's <dlfcn.h> (used under --system-libs too) had no dlinfo, RTLD_DI_* or Dl_info/dladdr, which glibc declares under _GNU_SOURCE. NetBSD's librumpuser/rumpuser_dl.c:414 `dlinfo(mainhandle, RTLD_DI_LINKMAP, &mainmap)` was the last of 488 rump files to fail (rump-pxx g40)."
status: done
owner: pxx2
---

# crtl's <dlfcn.h> lacked dlinfo and RTLD_DI_LINKMAP

lib/crtl/include/dlfcn.h: under _GNU_SOURCE, glibc's RTLD_DI_* values,
Dl_info, dlinfo and dladdr. Under --system-libs they bind to glibc's. In
crtl's own runtime, dlinfo fails through dlerror and dladdr answers 0.

<link.h> and <elf.h> still come from the host (with a warning), which works
for this use.

Test: test/c_dlinfo_linkmap.c (row c_dlinfo26): --system-libs against gcc,
and crtl's runtime against its own expected output.
