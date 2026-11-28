---
slug: feature-crtl-sigrtmin-and-sigrtmax
track: crtl
prio: 50
type: feature
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (Panorama all-pxx program: seatd 0.9.2's tests/poller.c through compdb.py replay)
tags: [crtl, signal]
summary: "<signal.h> had no SIGRTMIN/SIGRTMAX. crtl reserves no realtime signals (its threads use none), so a crtl program gets the kernel's range: 32 and 64. On the --system-libs path they are glibc's run-time values, __libc_current_sigrtmin()/max(), because NPTL keeps 32 and 33 and glibc's sigaction refuses them. This comes from a new __PXX_SYSTEM_SIGNAL__ predefine, like __PXX_SYSTEM_STDLIB__. Test: c_sigrt26, as a crtl program and as a --system-libs object, against gcc."
---

# SIGRTMIN and SIGRTMAX

seatd's poller test installs a handler on SIGRTMIN and raises it. That is the
one seatd unit that did not compile (35/36 before, 36/36 after).

The two values differ by mode on purpose. A crtl program owns the whole
realtime range. A glibc program does not: glibc's `SIGRTMIN` is 34 on
current x86-64, it is a function call, and `sigaction(32, ...)` fails with
EINVAL there. So the header asks glibc at run time on that path, exactly as
glibc's own header does.
