---
title: "crtl open_memstream had no position: ftell gave EBADF, rewind did nothing"
status: done
owner: claude-dupwt
prio: 70
area: crtl
---

open_memstream streams were append-only. ftell fell through to lseek(-1)
and failed with EBADF, and rewind did nothing, so a rewound stream kept
appending. dhcpcd builds every hook script's environment by rewinding one
memstream and calling ftell. Its hooks never ran ("make_env: Bad file
descriptor"), so resolv.conf was never written.

lib/crtl/src/stdio.c: the stream keeps its own position and high-water
mark (mpos/mhi). It doesn't use the read buffer's rpos/rlen, because
generic stdio code resets those. Behaviour now matches glibc:
- a write lands at the position and *sizep follows the position;
- the NUL is written only at the end of the data;
- fseek/fseeko take SEEK_SET, SEEK_CUR and SEEK_END, with SEEK_END
  counting from the current size;
- room never written reads as zeros;
- ftell/ftello return the position; rewind seeks to 0.
Test row c_ifamem26 compares against glibc's output.
