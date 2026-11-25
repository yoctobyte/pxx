---
slug: feature-crtl-gaps-from-xorg-libdrm-pixman
track: C
prio: 50
type: feature
status: done
owner: pxx2
created: 2026-11-25
closed: 2026-11-25
found-by: pxx2 (Path B Xorg on DRM)
tags: [crtl]
summary: "crtl additions the Xorg server, libdrm and pixman need: memfd_create and the MFD_* flags (<sys/mman.h>), F_ADD_SEALS/F_GET_SEALS and F_SEAL_* (<fcntl.h>, Xorg's MIT-SHM), clock_getres (<time.h>; clock_getres_time64 where that is the only call), pthread_sigmask (<signal.h>; returns the error number), pthread_attr_setscope/getscope with PTHREAD_SCOPE_SYSTEM/PROCESS (<pthread.h>; PROCESS is ENOTSUP, as glibc), and open_memstream (<stdio.h>; a FILE with no fd whose writes append to a heap buffer, *bufp/*sizep current after every write). Test c_xgaps26 against gcc."
---

# crtl gaps from Xorg, libdrm and pixman

open_memstream routes every FILE write through one sink (__crtl_swrite):
fwrite, fputs, fputc and the printf family. A memory stream renders
formatted output into a stack buffer first, as the fd path does, then
appends. fclose hands the buffer to the caller and returns the FILE to the
pool.
