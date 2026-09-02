---
slug: feature-c-corpus-busybox-258-applets-linked
title: "Rung 4: the 258-applet busybox userland — every applet the tree can build"
track: C
prio: 70
type: feature
status: open
created: 2026-09-02
found-by: frankD
owner: frankD
blocked-by: [feature-c-gnu-inline-asm-with-a-non-empty-template]
summary: "Rung 4, above the 141-applet rung 3 (done 2026-09-02): 258 applets, 400 translation units, one object each, one real link, byte-identical to the gcc oracle. Started at 13 failing TUs from 5 causes. As of 2026-09-02 ONE non-crtl cause remains — networking/tls_sp_c32.c's real x86-64 inline asm, whose failure is also the link failure. Everything else is closed: tcsetpgrp/statfs/select/posix_fallocate/cmsghdr/the PACKET constants/SSIZE_MAX in crtl, a 256-byte cap on block-scope string-initialised arrays, __VA_ARGS__ not being macro-expanded before substitution, and the host's inline-asm <asm/swab.h> reached through <linux/filter.h>. aarch64 stays out until --emit-obj has an object writer for it."
---

# Rung 4: 258 applets

Rung 3 (`feature-c-corpus-busybox-141-applets-linked`) met its bar at 141
applets / 265 TUs. This is the next one: **every applet the configured tree can
build**, which is 258 and 400 translation units.

**258 is the tree's own answer, not a target chosen by us.** It is what
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
| `telnetd.c`: no `FD_ZERO` | crtl `<sys/select.h>` + `select(2)` over three kernel spellings |
| `fallocate.c`: no `posix_fallocate` | crtl, with the two-error-conventions trap |
| `httpd.c`: a 331-byte `static const char suffixTable[]` | `bc8fa306b` — the block-scope string-array cap |
| `dhcpc.c`: "inline asm" | NOT busybox's asm: the host's `<asm/swab.h>`, reached through `<linux/filter.h>`. Shadowed. Also needed `cmsghdr`/`CMSG_*` and `AF_PACKET`/`SOL_PACKET` |
| `bc.c`: "undeclared identifier passed as argument 1" | `7d1b6cc12` — `__VA_ARGS__` was substituted raw, so an argument landing inside a self-named macro's own call was never expanded |

**Three of those seven were not what the diagnostic said.** dhcpc's asm was a
host header's; bc.c's "undeclared identifier" was a preprocessor gap four
thousand lines away; and six of the eight FAIL lines in the first run all
carried bc.c's error, because the harness reported
`grep error: | tail -1` over a build log shared by every translation unit. That
last one is fixed too — per-file logs — and it is the reason this ticket can
list causes at all.

## What is left

`networking/tls_sp_c32.c` takes an x86-64 inline-asm arm because pxx announces
`__GNUC__`. Its failure IS the link failure: the undefined
`curve_P256_compute_pubkey_and_premaster` is that one object missing, not a
separate defect. See `feature-c-gnu-inline-asm-with-a-non-empty-template`, and
do NOT "fix" it by un-announcing `__GNUC__`.

## Scope

x86-64 only, like rung 3. aarch64 needs an `--emit-obj` object writer
(`feature-a-object-output-for-arm32-and-aarch64`) and nothing smaller — 141-way
unity is impossible for gcc too, measured.
