---
slug: feature-b-crtl-function-gaps-at-394-busybox-applets
title: "crtl is missing ten POSIX/GNU functions that busybox calls at 394 applets"
track: B
prio: 55
type: feature
status: open
created: 2026-09-02
found-by: frankD
summary: "Ten distinct undeclared-function refusals across nine busybox TUs at the 394-applet scope, each stopping one applet dead: acct, mlock, scandir, ether_hostton, IN_MULTICAST, pause, nice, sched_getscheduler, sigisemptyset, plus one MTD ioctl constant that reaches bb_xioctl as an undeclared identifier. None is a compiler defect -- every one is a crtl surface gap, and each is small and independent, so this is a checklist rather than a design question. Measured against gcc/glibc as the oracle at binary 32a2ce1d9806; 507 of 521 TUs compiled, so these are the whole remainder together with the __BEGIN_DECLS group."
---

# The list, with the file that wants each

Measured 2026-09-02, busybox 1.36.1, 394 applets, 521 TUs, binary sha256
`32a2ce1d9806`. The gcc oracle links all 521 and agrees with the reference
busybox over 893 cases, so the oracle is sound at this width.

| function | header it belongs in | busybox TU |
| --- | --- | --- |
| `acct` | `unistd.h` | `init/bootchartd.c:230` |
| `mlock` | `sys/mman.h` | `miscutils/hdparm.c:1507` |
| `scandir` | `dirent.h` | `miscutils/tree.c:43` |
| `ether_hostton` | `netinet/ether.h` | `networking/ether-wake.c:134` |
| `IN_MULTICAST` | `netinet/in.h` (a macro) | `networking/libiproute/iptunnel.c:349` |
| `pause` | `unistd.h` | `procps/mpstat.c:726` |
| `nice` | `unistd.h` | `runit/chpst.c:469` |
| `sched_getscheduler` | `sched.h` | `util-linux/chrt.c:154` |
| `sigisemptyset` | `signal.h` (GNU) | `shell/hush.c:2126` |
| an MTD ioctl constant | `mtd/mtd-user.h` | `miscutils/nandwrite.c:106` |

`nandwrite.c` is the one worth reading before starting: the diagnostic is
*"undeclared identifier passed as argument 3 of `bb_xioctl`, where a pointer is
expected -- this would call/dereference through NULL"*, i.e. an undeclared
identifier silently became 0 and the frontend caught it at the call. That guard
is doing exactly its job; the missing thing is the constant, not the check.

`IN_MULTICAST` is a macro rather than a function and is reported as a call
because that is what an undeclared identifier followed by `(` looks like.
Do not go looking for a symbol to link.

## Scope note

This is the crtl **surface**, not its semantics. Each entry needs a declaration,
an implementation, and a row in a differential test against glibc — the pattern
`lib/crtl/src/regex.c` and `test/c_crtl_regex.c` established. `hush.c` is the
one whose applet is worth the most on its own (`hush` is a shell), and
`sigisemptyset` is its only blocker at this scope.
