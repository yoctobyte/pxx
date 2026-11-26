---
slug: feature-crtl-the-headers-a-hostless-target-lacks
track: C
prio: 70
type: feature
status: done
owner: pxx2
created: 2026-11-26
closed: 2026-11-26
found-by: frank-user (Nodisx on Rainyday, pxx with no host headers) and pxx2 (the same, replayed on the host)
tags: [crtl, cfront, nodisx, headers]
summary: "On the build host pxx falls back to /usr/include for a header crtl lacks, silently, so every Nodisx recipe's PASS could lean on glibc's headers; on the target (Rainyday) there are none. New: `--no-host-include` / PXX_NO_HOST_INCLUDE=1 drops only that fallback (crtl and -I stay, in their order; -nostdinc drops crtl too). With it, onsite-all.sh over all 14 recipes found six missing headers, all added: <ulimit.h> (mksh) with ulimit(), <values.h> (mksh), <sys/timeb.h> (GNU make) with ftime(), <ar.h> (GNU make), <linux/landlock.h> (xz's sandbox), <elf.h> and <link.h> (rumpnic). All 14 recipes now build with no host header. Tests c_nohost26, c_nohostref26, c_elfh26 (271 elf.h values against glibc's)."
---

# The headers a hostless target lacks

frank-user's first on-site run inside a Rainyday guest (pxx running there,
no /usr/include) built toybox and then stopped at mksh:
`lalloc.c: C include file not found: "ulimit.h"`. On the build host the same
compile had quietly found glibc's `/usr/include/ulimit.h` through pxx's
native-only host fallback (`<host system dirs>` in the search list).

## The switch

`-nostdinc` was no way to reproduce the guest: it also drops crtl's own
include directory, and putting it back with `-I` changes its place in the
search order. `--no-host-include` (and `PXX_NO_HOST_INCLUDE=1` in the
environment, which reaches every pxx a recipe runs, make's included) keeps
`-I` and crtl exactly as they are and only skips step 3 of the `<>` search;
the "not found" message no longer lists `<host system dirs>` under it, and
`--where` says it is off. `cpreproc.inc` (the search and the message),
`compiler.pas` (the option, `--where`), `defs.inc` (NoHostInc).

## What it found

`PXX_NO_HOST_INCLUDE=1 tools/nodisx/onsite-all.sh` over every recipe:

| header | recipe | what is used |
|---|---|---|
| `<ulimit.h>` | mksh | included when present; UL_* only without rlimits |
| `<values.h>` | mksh | included when present; nothing used |
| `<sys/timeb.h>` | GNU make | included by makeint.h |
| `<ar.h>` | GNU make | struct ar_hdr, ARMAG/SARMAG/ARFMAG (arscan.c) |
| `<linux/landlock.h>` | xz | the sandbox: ruleset attr, access bits, ABI query |
| `<elf.h>`, `<link.h>` | rumpnic | rumpuser_dl.c's link-map walk (dead under pxx: crtl's dlinfo fails) |

All written from the specifications (POSIX, the ELF gABI, the Landlock
documentation), not copied from glibc or the kernel. `ulimit()` and
`ftime()` are implemented, so the headers promise nothing that fails to
link. `<values.h>` is glibc's macro set exactly: names like `BITS` that a
larger set would add are ones programs define themselves.

Checks: `c_nohost26` (every new header's layouts and constants, ulimit set
and get in a child, ftime, a real landlock sandbox refusing a write) and
`c_elfh26` (all 247 `<elf.h>` constants and 18 struct sizes plus `link_map`'s
offsets) against gcc with glibc's headers; `c_nohostref26` (the switch refuses a
host-only header, the default still finds it). Every recipe's test.sh was
rerun with PXX_NO_HOST_INCLUDE=1.

The recipes' test.sh, all 14 with PXX_NO_HOST_INCLUDE=1: PASS. rumpnic's
first failed only on Rainyday's newer MAC check (rumpnictest.sh, f59f142,
added after that recipe was recorded); re-recorded, PASS. `ulimit()` and
`ftime()` use no syscall numbers (getrlimit/setrlimit, clock_gettime), so
they build for wasm32 too (ulimit is -1 there, with no rlimits).

`--where` keeps its `(not searched: cross target, or -nostdinc)` line, which a
test-core row matches; under the switch it prints a line of its own.

Alongside: make's test.sh bounds GNU make's suite at 40 minutes and kills,
by working directory, what it leaves running (the gcc build's misc/fopen-fail
left a make spinning for hours; the suite gives each test its own process
group, so a group kill missed it).

## A gap the switch cannot close

An absolute `#include "/home/..."` resolves on the host whatever the search
path. rumpnic had one (buildrump's tools/compat sys/stdint.h); frank-user's
record.sh makes it relative (0b92506fc9). A scan of every recipe's tree found
no other.

## Follow-up

`tools/nodisx/test-onsite-rainyday.sh` sets PXX_NO_HOST_INCLUDE=1 for its
host run, so the host and the guest see the same headers (frank-user).
