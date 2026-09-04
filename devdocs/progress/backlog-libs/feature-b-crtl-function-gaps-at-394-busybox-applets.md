---
slug: feature-b-crtl-function-gaps-at-394-busybox-applets
title: "crtl is missing nine POSIX/GNU functions plus the loff_t typedef that busybox calls at 394 applets"
track: B
prio: 55
type: feature
status: open
created: 2026-09-02
found-by: frankD
summary: "**THE loff_t ITEM IS LANDED (`0e439aaf5`) -- NINE FUNCTIONS REMAIN.** Nine distinct undeclared-function refusals across nine busybox TUs at the 394-applet scope, each stopping one applet dead: acct, mlock, scandir, ether_hostton, IN_MULTICAST, pause, nice, sched_getscheduler, sigisemptyset -- PLUS the `loff_t` typedef, which accounts for TWO more refusals on its own (flash_eraseall.c and nandwrite.c) and so is the whole remainder together with the __BEGIN_DECLS group. None is a compiler defect -- every one is a crtl surface gap, small and independent, so this is a checklist rather than a design question. CORRECTED 2026-09-04 (frankC), TWICE, both from the same probe: nandwrite.c was listed as a missing `an MTD ioctl constant` and is not -- MEMGETBADBLOCK IS defined (mtd-abi.h:152) and is argument 2, while the diagnostic named argument THREE, `&offs`, whose declaration `loff_t offs;` never parsed; and flash_eraseall.c was filed as a compiler lowering gap and is the same typedef. Prepending `typedef long long loff_t;` alone builds BOTH (500160B and 496704B objects, controls refuse), so ten items are nine and one line clears two refusals. Re-measured at binary 75c874f301fb77c2 / HEAD a8b606a3e: 507 of 521, the same fourteen. **x86-64 ONLY** -- the host-header fallback is native-only, so i386 refuses more and these rows close per-target, not once."
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
| ~~an MTD ioctl constant~~ **WRONG — see below** | — | `miscutils/nandwrite.c:106` |

`nandwrite.c` is the one worth reading before starting, and **the reason is now
the opposite of what this paragraph used to say.** It read:

> the diagnostic is *"undeclared identifier passed as argument 3 of
> `bb_xioctl`, where a pointer is expected"*, i.e. an undeclared identifier
> silently became 0 and the frontend caught it at the call. That guard is doing
> exactly its job; the missing thing is the constant, not the check.

The first half is right and the conclusion is wrong. **`MEMGETBADBLOCK` is
already defined** — `lib/crtl/include/mtd/mtd-abi.h:152` — and it is argument
**2**. The message said argument **3**, which is `&offs`, and `offs` is
undeclared because its declaration one line up is `loff_t offs;` and `loff_t`
does not exist. Same cause as flash_eraseall.c; see the eleventh item.

Worth keeping as a worked example rather than just deleting: nothing here
errored and nothing was sloppy. The diagnostic was PRECISE — it named the
argument index — and the reading substituted the argument a human eye lands on,
the shouty ioctl constant, for the one the compiler actually named. An
identifier standing in for the thing it names, believed because the sentence
around it was true.

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

**This one closes TWO of the fourteen refusals, and neither was filed as a
typedef.** One was filed as a C-frontend lowering gap
(`bug-c-ir-unsupported-ast-node-kind-1-in-flash-eraseall`) and is not one; the
other was filed in the table above as a missing MTD constant and is not one.
**All fourteen refusals at 394 applets are crtl surface, and nine of them are
what this ticket's checklist actually has left.**

One missing typedef, two TUs, and **three message shapes that share no
vocabulary** — which is the whole reason it was filed twice under two wrong
causes:

| TU | what the run printed |
| --- | --- |
| `flash_eraseall.c:156` | `IR_UNSUPPORTED: frontend could not lower AST node (kind 1) — a frontend gap, would miscompile` |
| `nandwrite.c:106` | `undeclared identifier passed as argument 3 of 'bb_xioctl', where a pointer is expected` |
| both | `warning: undeclared identifier 'loff_t' used as value (treated as 0)` |

The warning is the only one that names the cause, and it is a warning, sitting
above an error that blames the frontend. **Nobody was careless here: the loudest
line accused the compiler and the quiet line was right.**

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

**Re-run 2026-09-04 at binary `9c38c57228f289e2`, both TUs, with controls**, so
this is not a one-file result and not one that expired with the binary that
produced it:

| wrap | control (unmodified) | probe (typedef prepended) |
| --- | --- | --- |
| `miscutils_flash_eraseall.c` | refuses, `IR_UNSUPPORTED` at :156, **no object written** | `ok`, 496704 B |
| `miscutils_nandwrite.c` | refuses, argument-3 error at :106, **no object written** | `ok`, 500160 B |

The control column is the point: it is drawn from the same population, it
refuses for the *same* message the 394-applet run recorded, and it leaves no
object behind — so the probe's `ok` cannot be a stale artifact of an earlier
build. The two object sizes also differ from each other and from the 502192 B
above, which is what a real compile of three different inputs looks like.

**Width note, because this is the class that is invisible on x86-64:**
`__kernel_loff_t` is `long long` on *every* architecture, deliberately — see
`lib/crtl/include/mtd/mtd-abi.h:14`, *"MEMGETBADBLOCK TAKES A __kernel_loff_t —
64 bits on EVERY architecture"*. So `loff_t` must be `long long`, **not** `long`
or `off_t`: on i386 the latter two are 32 bits and the ioctl would read half an
argument. Whoever takes this should put it where `__kernel_loff_t` already is,
or define it in terms of it, rather than picking a width at the new site.

Not fixed here: `lib/crtl` is B's lane and this was found from C. Filed rather
than fixed on frankuser's explicit routing.

## LANDED 2026-09-04: the loff_t item, with its per-target rows (frankD, `0e439aaf5`)

`typedef long long loff_t;` in `lib/crtl/include/sys/types.h`. Measured on the
real busybox TUs at binary sha256 `08f25ff41d20`, not on the reduction:

| target | `flash_eraseall.c` | `nandwrite.c` |
| --- | --- | --- |
| x86-64 | **compiles** (30 objects linked, no refusals) | **compiles** |
| i386 | still refuses — `linux/jffs2.h` not found | **compiles** |

**This is the (TU, target) claim measured rather than predicted.** One typedef
clears two TUs on x86-64 and one on i386, and `flash_eraseall` on i386 has a
second, independent blocker that belongs to
`bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS`. Closing this item on the
x86-64 row alone would have closed it green with that blocker untouched.

`long long`, never `long` or `off_t`: MEMGETBADBLOCK carries the width in its
ioctl NUMBER via `_IOW`, so a narrower spelling compiles everywhere and issues
a different request on every ILP32 target. Asserted as a RELATION in row 16 of
`test/c_crtl_mtd_timex_kd_caps.c` (`sizeof(loff_t) == sizeof(long long)`), so it
carries no per-target constant; all 16 rows are byte-identical to
`gcc -D_GNU_SOURCE`.

One oracle note for whoever diffs this next: **glibc gates `loff_t` behind
`__USE_MISC`**, so a plain `gcc` build cannot see it and the row needs
`-D_GNU_SOURCE`. crtl defines it unconditionally — the accept-more direction,
and unobservable to a program that does not use the type.
