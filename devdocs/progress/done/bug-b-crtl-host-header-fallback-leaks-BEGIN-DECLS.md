---
slug: bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS
title: "The host-header fallback is native-only, so x86-64 compiles busybox against glibc and hides 15 missing crtl headers"
track: B
prio: 65
type: bug
status: done
created: 2026-09-02
found-by: frankD
summary: "RESOLVED 2026-09-04 in four batches: all nine busybox translation units that refused at i386 now compile, and the closing measurement is a run over ALL 400 TUs rather than the nine that were named -- the ticket's own list was a lower bound and proved it twice (raidautorun wanted two headers, the second invisible until the first existed; five of the fifteen headers already existed). THE HEADERS WERE PROVIDED RATHER THAN THE FALLBACK FIXED, which is what the original analysis asked for: making the native fallback supply glibc's preamble would have made x86-64 green while i386 still could not build those TUs, and the divergence would then have read as an i386 defect. Two of the additions are implementations rather than shadow headers -- glob(3) over fnmatch+dirent, and a DNS resolver (resolv.h, arpa/nameser.h, ~1000 lines) -- both diffed against glibc on five targets. Three defects the value diff found that reasoning did not: glob() must NOT filter . and .. (glibc returns four entries for \".*\", not two); inet_ntop(AF_INET6) was missing entirely and failed as a WRONG ANSWER, printing the caller's uninitialised buffer so 2001:db8::1 came out as the previous record's 93.184.216.34; and ns_name_pton returns 0/1 rather than a length, which is invisible for a one-byte name and had res_nmkquery building its question section from the wrong bytes. Two chosen divergences recorded in known-incompat/incompat-b-crtls-dns-parser-refuses-two-malformed-packets-glibc-accepts. NOT fixed here: gethostbyname still returns NULL, _res is process-wide rather than per-thread (blocked on the errno TLS ticket), and IPv6 nameservers in resolv.conf are parsed and dropped."
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

---

## RESOLVED 2026-09-04 — all nine named TUs compile at i386, in four batches

**The headers were provided, not the fallback fixed**, which is what the
summary above asked for and it was the right call: making the native fallback
supply glibc's preamble would have made x86-64 green while i386 still could not
build those TUs at all, and the divergence would then have read as an i386
defect.

| batch | headers | TUs unblocked |
| --- | --- | --- |
| 1 | `linux/major.h`, `linux/raid/md_u.h`, `linux/random.h`, `linux/rfkill.h`, `sys/random.h` (+`src/sys/random.c`) | raidautorun, rfkill, seedrng |
| 2 | `sys/xattr.h`, `sys/inotify.h`, 62 missing `errno.h` names (+ two sources) | inotifyd, setfattr |
| 3 | `linux/fb.h`, `mtd/ubi-user.h` | fbsplash, ubi_tools |
| 4 | `glob.h` (+`src/glob.c`), `resolv.h`, `arpa/nameser.h`, `arpa/nameser_compat.h` (+ two sources), and AF_INET6 in `inet_ntop`/`inet_pton` | hush, nslookup |

`networking/interface.c` needed nothing new — it cleared once a header another
TU wanted was in place, which is a second instance of the lesson below.

### THE TICKET'S LIST WAS A LOWER BOUND AND IT PROVED IT TWICE

It named **one header per TU** because it was built from FIRST refusals.
`raidautorun.c` wanted `<linux/major.h>` and then `<linux/raid/md_u.h>`, the
second invisible until the first existed. Five of the fifteen headers it named
already existed by the time work started. **Re-measure a list of this shape
before working from it** — and the closing measurement is a full run over all
400 translation units, not the nine that were named.

### Two implementations, not shadow headers

`glob.h` and `resolv.h` are the first entries here that needed real code rather
than a transcription: 291 lines of `glob()` over `fnmatch` + `dirent`, and
~1000 lines of DNS across `nameser.c` and `resolv.c`. Both are diffed against
glibc on five targets, and both found something the diff alone would not have:

- **`glob()`**: the first draft filtered `.` and `..` out of the readdir loop.
  glibc does not — `glob(".*")` returns four entries, not two. `FNM_PERIOD` is
  what keeps them out of a plain `*` and is the only thing that should.
- **`inet_ntop(AF_INET6, ...)` was missing entirely**, and it failed as a
  WRONG ANSWER: it returned NULL, the AAAA row printed its uninitialised
  buffer, and `2001:db8::1` came out as `93.184.216.34` — the previous
  record's IPv4 address, off the stack, with nothing erroring anywhere.
- **`ns_name_pton()` returns 0 or 1, not a length**, which the first draft got
  wrong in a way that is invisible for a one-byte name: `ns_name_pton(".")`
  answers 1 under both readings. `res_nmkquery` was advancing its cursor by
  one byte and building the question section out of the wrong bytes.

### Two chosen divergences, recorded

`known-incompat/incompat-b-crtls-dns-parser-refuses-two-malformed-packets-glibc-accepts`
— crtl refuses a forward DNS compression pointer and a reply with QR clear;
glibc accepts both. Both crtl answers are the RFC-conforming ones and no
conforming server emits either shape.

### What this ticket did NOT fix

- `gethostbyname()` still returns NULL (`src/netinet/in.c`). The res_* layer
  it would need now exists, so that is a much smaller job than it was, but it
  is a separate one.
- `_res` is one process-wide struct, not one per thread, blocked on
  [[bug-a-errno-is-one-global-across-all-threads-so-a-thread-reads-another-threads-failure]]
  for exactly the same reason errno is.
- IPv6 nameservers in `/etc/resolv.conf` are parsed and dropped: `nsaddr_list`
  is an array of `sockaddr_in`. A resolv.conf with only IPv6 servers leaves
  `nscount` 0 and every lookup fails visibly, rather than asking the wrong
  server.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
