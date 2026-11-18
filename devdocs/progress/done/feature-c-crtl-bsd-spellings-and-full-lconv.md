---
track: C
tags: [crtl, bsd, locale, select, fcntl, fbdev, pathb, tinyx]
prio: 70
type: feature
blocked-by: []
summary: "crtl now has the BSD/glibc spellings TinyX's os/ and kdrive/ use: setlinebuf, getdtablesize, fd_mask/NFDBITS/__FDS_BITS, FNDELAY/FNONBLOCK/FASYNC, F_SETOWN/F_GETOWN, the full struct lconv in glibc's member order, and a <linux/fb.h> that brings __u16 (via <linux/types.h>)."
status: done
owner: pxx2
---

# crtl: BSD spellings and the full struct lconv

These are the gaps between crtl and glibc that the TinyX Xfbdev replay hit:

- **struct lconv:** all of glibc's members, in glibc's order, so that a
  --system-libs build and a crtl build agree on every offset. localeconv fills
  the "C" locale values: empty strings and CHAR_MAX.
- **setlinebuf:** a no-op. A crtl stream writes straight through, so every
  line arrives at least as early as line buffering would deliver it.
- **getdtablesize:** returns sysconf(_SC_OPEN_MAX).
- **<sys/select.h>:** fd_mask, NFDBITS and glibc's `__FDS_BITS(set)`. Xpoll.h
  uses that macro when it exists and otherwise falls back to glibc's private
  member name.
- **<fcntl.h>:** FNDELAY, FNONBLOCK, FASYNC, F_SETOWN (8) and F_GETOWN (9).
- **<linux/fb.h>:** includes <linux/types.h>, as the kernel's header does.

Test: test/c_crtl_bsd_lconv_bits.c (row c_bsdlconv26) against gcc on x86-64
and i386.
