---
slug: feature-crtl-toybox-surface
track: C
prio: 50
type: feature
status: done
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [crtl, toybox]
blocked-by: []
summary: "crtl grew what toybox 0.8.15 defconfig reaches: sigjmp_buf/sigsetjmp/siglongjmp; the *at family over real dirfds (fstatat, fchmodat, mkdirat, mknodat, mkfifoat, openat, unlinkat, readlinkat, fchownat, faccessat, linkat, symlinkat, renameat); full _SC_/_PC_/_CS_ (sys/_confname.h), sysconf long tail, pathconf/fpathconf/confstr; getcwd(NULL,n) allocates; getopt '+'/'-' and POSIXLY_CORRECT; getentropy; posix_fadvise; locale_t objects (C/POSIX only); langinfo; C-locale wide chars and wcwidth; utmpx reader; getifaddrs (IPv4); iconv (UTF-8/16/32, ASCII, LATIN1); eventfd; prlimit; mlockall; a proper siginfo_t; and uapi headers (linux/sched, rtc, soundcard, nbd, gpio v1, fs, if_vlan, cdrom, scsi/sg, scsi/scsi, sys/ttydefaults). Layouts and numbers checked against gcc on x86-64 and i386."
---

# crtl: the toybox surface

Before the uapi headers existed, a native x86-64 build silently resolved them
from the HOST, and every cross target failed to find them. Test:
`test/c_crtl_toybox_surface.c` (argv[1] = a fresh scratch dir), x86-64 and
i386, expected = gcc. getopt '+' and getcwd(NULL) were also bugs reported by
pixx-f2 (busybox/toybox).
