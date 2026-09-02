---
slug: feature-c-corpus-busybox-257-applets-linked
title: "Rung 4: the 257-applet busybox userland — every applet the tree can build"
track: C
prio: 70
type: feature
status: done
created: 2026-09-02
found-by: frankD
owner: frankD
blocked-by: [feature-c-gnu-inline-asm-with-a-non-empty-template]
summary: "MET 2026-09-02, x86-64: 257 applets, 400 translation units, one object each, one real link, and the linked binary byte-identical to the gcc oracle over all 619 cases (an oracle that itself agrees with busybox's own separately-linked build). Rung 4, above the 141-applet rung 3. Started at 13 failing TUs from 5 causes; every one was named by attempting the target. Closed on the way: tcsetpgrp/statfs/select/posix_fallocate/cmsghdr/the PACKET constants/SSIZE_MAX in crtl, the crtl impl splice point (a header included from the middle of another header spliced its impl ahead of the outer header's own declarations), a 256-byte cap on block-scope string-initialised arrays, __VA_ARGS__ not being macro-expanded before substitution, the host's inline-asm <asm/swab.h> reached through <linux/filter.h>, GNU inline asm with a non-empty template (a peer), and a FILE-SCOPE array initialiser past 256 elements dropped silently, which sized the generated applet_main[] to ONE entry and segfaulted every applet that did real work. aarch64 stays out until --emit-obj has an object writer for it."
---

# Rung 4: 257 applets

Rung 3 (`feature-c-corpus-busybox-141-applets-linked`) met its bar at 141
applets / 265 TUs. This is the next one: **every applet the configured tree can
build**, which is 257 and 400 translation units.

**257 is the tree's own answer, not a target chosen by us.** It is what
`enabled_applets()` reports with everything switched on; the harness asserts the
count against `include/applet_tables.h` rather than trusting a NUM_APPLETS
proxy, after that proxy claimed the tree had extras it did not have.

## Where it stands

The gcc oracle links all 400 objects and agrees with upstream's own build over
621 cases, so the bar is reachable and the comparison is real.

Closed by attempting it, 2026-09-02, all measured rather than triaged:

| cause | closed by |
| --- | --- |
| `getty.c`: no `tcsetpgrp` | crtl termios pair, `1799aad1a`'s predecessor |
| `switch_root.c`: no `statfs` | crtl `src/sys/statfs.c`, plus the whole `__NR3264_` family missing from `<sys/syscall.h>` for aarch64/riscv32 |
| `telnetd.c`: no `FD_ZERO` | crtl `<sys/select.h>` + `select(2)` over three kernel spellings, then `06b6b47e4` — libbb.h reaches `fd_set` only through `<sys/types.h>`, and giving `<sys/types.h>` glibc's `#include <sys/select.h>` exposed a splice-point bug the crtl auto-pull has had all along |
| `fallocate.c`: no `posix_fallocate` | crtl, with the two-error-conventions trap |
| `httpd.c`: a 331-byte `static const char suffixTable[]` | `bc8fa306b` — the block-scope string-array cap |
| `dhcpc.c`: "inline asm" | NOT busybox's asm: the host's `<asm/swab.h>`, reached through `<linux/filter.h>`. Shadowed. Also needed `cmsghdr`/`CMSG_*` and `AF_PACKET`/`SOL_PACKET` |
| `bc.c`: "undeclared identifier passed as argument 1" | `7d1b6cc12` — `__VA_ARGS__` was substituted raw, so an argument landing inside a self-named macro's own call was never expanded |

**The count is 257, not the 258 first written here.** Both readings agree —
`NUM_APPLETS` in the configured `include/applet_tables.h`, and the applet list
the harness prints and cross-checks against that table in both directions. The
258 was an off-by-one carried into this ticket, the inline-asm ticket and two
comments in the harness before anything counted it twice.

**Three of those seven were not what the diagnostic said.** dhcpc's asm was a
host header's; bc.c's "undeclared identifier" was a preprocessor gap four
thousand lines away; and six of the eight FAIL lines in the first run all
carried bc.c's error, because the harness reported
`grep error: | tail -1` over a build log shared by every translation unit. That
last one is fixed too — per-file logs — and it is the reason this ticket can
list causes at all.

## Confirmed 2026-09-02 on a clean tree

`tools/busybox_diff.sh --targets x86_64 --separate --applets <all 257>` at
`192c91a4b42f`: the gcc oracle links 400 objects and agrees with busybox's own
build over 619 cases; pxx compiles **399 of 400**. The one refusal is
`networking/tls_sp_c32.c` and the one undefined symbol in the link is
`curve_P256_compute_pubkey_and_premaster`, which is that object and nothing
else. `--separate` is required: `coreutils/test.c` and `shell/ash.c` claim
ordinary identifiers through their `globals` macros and collide in both include
orders, so no unity can hold the whole corpus — gcc's ceiling too, not pxx's.

## Met, 2026-09-02

`tools/busybox_diff.sh --targets x86_64 --separate --applets <all 257>` at
compiler `20953dc0444e`: **GREEN**. 400 objects, one real link, and the linked
binary agrees with the gcc oracle over all 619 cases — an oracle that itself
agrees with busybox's own separately-linked build.

The last two blockers, both named by the attempt rather than by triage:

- `networking/tls_sp_c32.c`'s x86-64 inline asm, taken because pxx announces
  `__GNUC__`. Resolved by a peer
  (`feature-c-gnu-inline-asm-with-a-non-empty-template`); the undefined
  `curve_P256_compute_pubkey_and_premaster` was that one object missing and
  not a separate defect. It was never right to "fix" it by un-announcing
  `__GNUC__`.
- **A file-scope array initialiser past 256 elements, dropped silently.**
  This one only exists at this rung: `include/applet_tables.h` is GENERATED,
  one `<applet>_main` per applet, so `applet_main[]` crossed 256 for the
  first time at 257 applets. All 400 objects compiled AND LINKED, and then
  every applet that did real work segfaulted through a one-element table —
  while the identical build at 141 applets had been byte-identical to gcc.
  Fixed in the same-day commit that adds
  `test/c_global_array_init_over_256.c`.

## What this claim does NOT say

**"pxx compiles and links busybox, byte-identical to gcc" is the claim.
"crtl is enough to build busybox" is NOT, and it is the sentence a reader
supplies for themselves.** This build emits **1053** `resolved from the host
system (/usr/include), not pxx's own headers` warnings over **110** distinct
headers. Measured the day this closed, by attempting the SAME 400 translation
units for i386, where there is no host to fall back on: 64 of them stop on a
crtl header gap, 34 distinct headers, led by `regex.h` and `netinet/udp.h` at
7 translation units each. On x86-64 not one of those is visible, because the
fallback answers every time and answers correctly.

That is the second architecture's ticket
(`feature-c-corpus-busybox-i386-the-second-architecture`), not a defect in this
one — but it belongs here, because this is the page anyone quoting the GREEN
will read.

## Scope

x86-64 only, like rung 3. aarch64 needs an `--emit-obj` object writer
(`feature-a-object-output-for-arm32-and-aarch64`) and nothing smaller — 141-way
unity is impossible for gcc too, measured.

## Log
- 2026-09-02 — GREEN: 400 translation units, 400 objects, one real link, all 619 cases byte-identical to the gcc oracle, at compiler 20953dc0444e.
- 2026-09-02 — resolved, commit bc030527e.
