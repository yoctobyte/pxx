---
slug: feature-b-crtl-function-gaps-at-394-busybox-applets
title: "crtl is missing ten POSIX/GNU functions plus the loff_t typedef that busybox calls at 394 applets"
track: B
prio: 55
type: feature
status: open
created: 2026-09-02
found-by: frankD
summary: "Ten distinct undeclared-function refusals across nine busybox TUs at the 394-applet scope, each stopping one applet dead: acct, mlock, scandir, ether_hostton, IN_MULTICAST, pause, nice, sched_getscheduler, sigisemptyset, plus one MTD ioctl constant that reaches bb_xioctl as an undeclared identifier. None is a compiler defect -- every one is a crtl surface gap, and each is small and independent, so this is a checklist rather than a design question. Measured against gcc/glibc as the oracle at binary 32a2ce1d9806; 507 of 521 TUs compiled, so these are the whole remainder together with the __BEGIN_DECLS group. ELEVENTH ITEM ADDED 2026-09-04 (frankC): the `loff_t` TYPEDEF, which turns out to be the fourteenth refusal too -- flash_eraseall was mis-filed as a compiler lowering gap and is crtl. One line, proven."
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


## ELEVENTH ITEM — the `loff_t` typedef (frankC, 2026-09-04)

**This one also closes the fourteenth refusal**, which was filed separately as a
C-frontend lowering gap (`bug-c-ir-unsupported-ast-node-kind-1-in-flash-eraseall`)
and is not one. **All fourteen refusals at 394 applets are crtl surface.**

crtl declares `__kernel_loff_t` (`lib/crtl/include/linux/types.h:39`) but not
`loff_t`, which glibc provides from `<sys/types.h>` as a GNU extension. So
`miscutils/flash_eraseall.c:156`

```c
loff_t offset = erase.start;
ret = ioctl(fd, MEMGETBADBLOCK, &offset);
```

is not parsed as a declaration at all. `loff_t` becomes an undeclared identifier
`treated as 0`, `offset` likewise, and `&offset` is then the address of an
integer literal — which the IR cannot lower, correctly.

**The fix, and it is proven rather than proposed:**

```c
typedef long long loff_t;      /* alongside the existing __kernel_loff_t */
```

Prepending exactly that to the busybox wrapper — nothing else changed — turns
the refusal into a **502192-byte object, rc=0, zero IR_UNSUPPORTED**.

**Width note, because this is the class that is invisible on x86-64:**
`__kernel_loff_t` is `long long` on *every* architecture, deliberately — see
`lib/crtl/include/mtd/mtd-abi.h:14`, *"MEMGETBADBLOCK TAKES A __kernel_loff_t —
64 bits on EVERY architecture"*. So `loff_t` must be `long long`, **not** `long`
or `off_t`: on i386 the latter two are 32 bits and the ioctl would read half an
argument. Whoever takes this should put it where `__kernel_loff_t` already is,
or define it in terms of it, rather than picking a width at the new site.

Not fixed here: `lib/crtl` is B's lane and this was found from C. Filed rather
than fixed on frankuser's explicit routing.
