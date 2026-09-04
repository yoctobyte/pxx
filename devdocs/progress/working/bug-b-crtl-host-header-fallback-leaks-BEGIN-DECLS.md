---
slug: bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS
title: "The host-header fallback is native-only, so x86-64 compiles busybox against glibc and hides 15 missing crtl headers"
track: B
prio: 65
type: bug
status: working
created: 2026-09-02
found-by: frankD
summary: "**THE HOST-HEADER FALLBACK IS NATIVE-ONLY, SO x86-64 HAS BEEN COMPILING busybox AGAINST GLIBC'S HEADERS AND HIDING 15 MISSING crtl HEADERS.** On x86-64 an unknown `<h>` resolves from /usr/include with a warning; on any cross target the search path has no /usr/include and it is a hard `C include file not found`. Measured 2026-09-04 at the 394-applet scope: 3 TUs refuse on x86-64 (all `stray token: __BEGIN_DECLS`, because glibc's sys/xattr.h uses it at line 25 without including <sys/cdefs.h>) and **16 TUs refuse on i386**, naming 15 headers crtl does not have. The __BEGIN_DECLS symptom was the tip: it only appears for the handful of host headers that happen to use that macro, so it undercounted the gap by five to one. Fix is to PROVIDE the headers -- making the fallback establish glibc's preamble would paper over x86-64 while i386 still cannot build those TUs at all, and the divergence would then read as an i386 defect."
owner: franks-ab
---

# One cause, three refusals

Measured 2026-09-02, binary sha256 `32a2ce1d9806`, busybox 1.36.1 at 394
applets / 521 TUs.

```c
/* bd1.c -- FAILS: pascal26:25: error: stray token at top level: '__BEGIN_DECLS' */
#include <sys/xattr.h>
int main(void){return 0;}

/* bd2.c -- COMPILES */
#include <sys/cdefs.h>
#include <sys/xattr.h>
int main(void){return 0;}
```

Both emit `warning: #include <sys/xattr.h> resolved from the host system
(/usr/include), not pxx's own headers`. That warning is the instrument working,
and it named the cause before the error did.

## The mechanism, in full

`/usr/include/x86_64-linux-gnu/sys/xattr.h` opens with `__BEGIN_DECLS` on line
25 and **does not include `<sys/cdefs.h>` itself**. Under glibc that is safe:
something upstream in a normal include chain has already pulled `<features.h>`,
which pulls `<sys/cdefs.h>`. In a pxx TU nothing does, so the macro is undefined
and its token reaches the top level, where it is correctly reported as a stray
token. `lib/crtl/include/sys/cdefs.h:5` defines `__BEGIN_DECLS` — it is just
never included on this path.

So there are two candidate fixes and they are not equivalent:

1. **Provide the three headers in crtl** (`sys/inotify.h`, `sys/random.h`,
   `sys/xattr.h`). Removes the host fallback for these TUs entirely. This is
   the real fix; the host header is an ABI hazard beyond this macro, which is
   what the warning is about.
2. Make the host-fallback path establish glibc's preamble first. Cheaper, wider
   blast radius, and it keeps compiling against host headers — it converts a
   loud failure into a silent ABI dependency, which is the wrong direction.

Prefer 1. 2 is only interesting if the same leak turns up in host headers we
have no intention of shadowing.

## Why it took 394 applets to see

No smaller applet set pulled these three sources in. The refusal is not new;
the coverage is.

# THE i386 MEASUREMENT, which reframes this ticket

Measured 2026-09-04, binary sha256 `1968c7a7da57`, commit `5f598d4a7`, at the
394-applet scope (`tools/busybox-applets-394.txt`). Reproduced in two lines,
independent of busybox:

```
$ pascal26              bd1.c     # #include <sys/xattr.h>
pascal26:1: warning: ... resolved from the host system (/usr/include), not
                     pxx's own headers -- ABI/macro mismatches may silently misbehave
pascal26:25: error: stray token at top level: '__BEGIN_DECLS'

$ pascal26 --target=i386 bd1.c
pascal26:1: error: C include file not found: "sys/xattr.h"
            (searched: .../lib/crtl/include/, ...)        <- no /usr/include
```

**The fallback is native-only, and that is correct** -- host headers are the
host's ABI. The consequence is not: every crtl header gap is INVISIBLE on
x86-64 for as long as glibc has a header of that name, and visible on every
cross target. x86-64 was not passing those TUs; it was compiling them against
somebody else's headers.

## The 15 headers, and the 16 TUs that want them (i386)

| header | busybox TU |
| --- | --- |
| `glob.h` | `shell/hush.c` |
| `resolv.h` | `networking/nslookup.c` |
| `sys/inotify.h` | `miscutils/inotifyd.c` |
| `sys/vt.h` | `loginutils/vlock.c` |
| `sys/xattr.h` | `miscutils/setfattr.c` |
| `linux/fb.h` | `miscutils/fbsplash.c` |
| `linux/if.h` | `networking/ether-wake.c`, `ifenslave.c`, `ifplugd.c` |
| `linux/if_arp.h` | `networking/libiproute/ll_types.c` |
| `linux/if_vlan.h` | `networking/libiproute/iplink.c` |
| `linux/jffs2.h` | `miscutils/flash_eraseall.c` |
| `linux/major.h` | `miscutils/raidautorun.c` |
| `linux/random.h` | `miscutils/seedrng.c` |
| `linux/rfkill.h` | `miscutils/rfkill.c` |
| `mtd/ubi-user.h` | `miscutils/ubi_tools.c` |

`linux/random.h` is wanted by `seedrng.c` **as well as** `sys/random.h`; the
x86-64 run reported the latter via __BEGIN_DECLS and the i386 run stops at the
former, so both are missing and neither run alone says so.

## Why __BEGIN_DECLS was a bad name for this

The macro leak happens only for host headers that spell `__BEGIN_DECLS` without
pulling `<sys/cdefs.h>` themselves. That is 3 of the 15. **The symptom
undercounted its own cause by five to one**, and a fix aimed at the symptom --
pre-including crtl's `sys/cdefs.h` on the fallback path -- would have closed
this ticket green with twelve headers still missing and i386 still refusing all
sixteen TUs. The slug is kept so existing citations resolve; the summary is the
part that had to change.

## Consequence for anyone measuring on x86-64 only

`bug-c-ir-unsupported-ast-node-kind-1-in-flash-eraseall` was root-caused on
x86-64 as a missing `loff_t` (correct, and fixed). On i386 the same TU never
reaches that line -- it stops at `linux/jffs2.h`. **A TU can have two
independent blockers with only the native one visible**, so "fixed on x86-64"
is not "fixed", and a per-target row is what closes an item here.
