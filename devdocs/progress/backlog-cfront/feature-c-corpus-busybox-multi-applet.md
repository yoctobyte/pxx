---
slug: feature-c-corpus-busybox-multi-applet
title: "busybox beyond cat: the multi-applet binary, and ash"
track: C
prio: 70
type: feature
blocked-by: []
status: new
created: 2026-08-31
owner: ""
summary: "Rung 2 of feature-busybox-kiosk-selfhosting-target. Rung 1 (cat, byte-identical to gcc on x86-64 + aarch64) is done and REACHED ONLY 25 of libbb's ~145 TUs; the applet-dispatch table and the TUs cat never touches are what is untested. First bar: a two-applet binary that dispatches by argv[0]/argv[1]. Second: ash. tools/busybox_cat_diff.sh is the harness to extend, not to rewrite."
---

# busybox rung 2 — more than one applet, then `ash`

Rung 1 resolved 2026-08-31: `busybox cat` built by pxx from upstream
unvendored source, byte-identical to gcc's build and to upstream's own
separately-linked `busybox_CAT`, on x86-64 and aarch64. What it did **not**
establish is the whole of this ticket.

## What rung 1 leaves open

- **Applet dispatch.** `cat` was built `NUM_APPLETS 1`, which sets
  `SINGLE_APPLET_MAIN` and compiles the dispatch table *out*. The
  `__attribute__((section(".rodata.applets")))` table, `applet_names`,
  `run_applet_and_exit` and `argv[0]` dispatch are all untested.
- **120 of 145 libbb TUs.** `cat`'s link pulled 25 archive members. The rest
  is where the surface crtl currently declines to declare gets called for
  real: `getpwnam`/`getgrgid` (`<pwd.h>`, `<grp.h>` are types-only today),
  `statfs`, `getrlimit`, `getmntent`. Each is a decision when it arrives —
  PAL work, a crtl module, or a genuine "this applet is out of scope" — and
  none should become a stub that returns a wrong answer.
- **`ash`.** Its own job: `fork`/`exec`/`wait` are the process model, and the
  PAL's coverage there is what decides whether this rung is a week or a day.
  Establish the multi-applet binary first, on applets that do not fork.

## Suggested first bar

A **two-applet** binary (`cat` + `echo`, say) that dispatches correctly by
both `argv[0]` (busybox's symlink convention) and `busybox <applet>`, with
output byte-identical to a gcc build of the same configuration, on x86-64 and
aarch64.

## Harness

Extend `tools/busybox_cat_diff.sh`; do not start over. It already fetches
nothing and asks for nothing — it configures the tree itself, because
`make defconfig && make` does not build 1.36.1 against current kernel headers
(`networking/tc.c`), which also rules out upstream's `make_single_applets.sh`.
The pieces to generalise are the applet list in the configure step and the
`#include` set in `tools/busybox_cat_unity.c`, which is read off
`busybox_unstripped.map`.

**Keep both oracles.** gcc on the same unity, *and* upstream's own
separately-linked binary. A unity build can share a mistake with itself; it
cannot share one with a real link — and on rung 1 the unity was the thing that
was wrong (an include-order bug that made gcc's build segfault), found only
because the second oracle disagreed.
