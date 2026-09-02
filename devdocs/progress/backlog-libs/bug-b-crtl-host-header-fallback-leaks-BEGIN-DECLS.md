---
slug: bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS
title: "crtl has no sys/inotify.h, sys/random.h or sys/xattr.h, and the host fallback then leaks __BEGIN_DECLS"
track: B
prio: 55
type: bug
status: open
created: 2026-09-02
found-by: frankD
summary: "Three busybox TUs refuse identically at the 394-applet scope -- miscutils/inotifyd.c, miscutils/seedrng.c and miscutils/setfattr.c, each `stray token at top level (not a declaration): '__BEGIN_DECLS'`. ONE cause, three symptoms: crtl does not provide sys/inotify.h, sys/random.h or sys/xattr.h, so pxx falls back to /usr/include (it says so, as a warning), and glibc's own sys/xattr.h uses __BEGIN_DECLS at line 25 WITHOUT including <sys/cdefs.h> -- it relies on an earlier glibc header having pulled <features.h> in, which nothing in a pxx TU does. crtl's own sys/cdefs.h defines the macro correctly; it is simply never reached. Two-line reproducer below."
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
