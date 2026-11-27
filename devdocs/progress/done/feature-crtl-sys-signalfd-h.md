---
slug: feature-crtl-sys-signalfd-h
track: C
prio: 55
type: feature
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (Panorama's bus helper through pxx: libsystemd's sd-event.h includes <sys/signalfd.h>)
tags: [crtl, linux, panorama]
summary: "crtl had no <sys/signalfd.h>, so the host's was used, and glibc's needs __BEGIN_DECLS from glibc's own <stdint.h> chain: `stray token at top level: '__BEGIN_DECLS'` in Panorama's src/helpers/bus.c (via systemd/sd-bus.h -> sd-event.h). Added from the signalfd(2) manual page: struct signalfd_siginfo (128 bytes, every field the page lists), SFD_CLOEXEC/SFD_NONBLOCK as the open flags, and signalfd() over signalfd4 with the kernel's 8-byte sigset. Test c_signalfd26: layout and a SIGUSR1 round trip, identical to gcc + glibc."
---

# <sys/signalfd.h>

Panorama's D-Bus helper (src/helpers/bus.c) includes <systemd/sd-bus.h>,
which brings <sys/signalfd.h> in through sd-event.h. With no crtl copy, the
host's glibc header was read. It opens with `__BEGIN_DECLS` without
including <sys/cdefs.h>, because under glibc <stdint.h> has already pulled it
in. crtl's <stdint.h> does not, so the unit was refused.

The header is written from the manual page, not copied. The record's offsets
(signo 0, pid 12, uid 16, int 44, ptr 48, addr 72, addr_lsb 80, syscall 84,
call_addr 88, arch 96, size 128) are compared with glibc's in the test.
signalfd() calls signalfd4 with the kernel's sigset size (_NSIG/8 = 8),
like eventfd.c.

Test test/c_signalfd.c (c_signalfd26): the layout; SFD_* equal the open flags;
close-on-exec and non-blocking set on the fd; an empty non-blocking read
fails; a blocked SIGUSR1 sent to self is read back with the right signo, pid
and uid. Identical to gcc.

With it, Panorama's four helpers build through pxx (status and index as
plain crtl programs; icons and bus as --system-libs objects linked with
libpng / libsystemd).
