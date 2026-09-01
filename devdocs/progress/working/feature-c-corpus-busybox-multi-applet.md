---
slug: feature-c-corpus-busybox-multi-applet
title: "busybox beyond cat: the multi-applet binary, and ash"
track: C
prio: 70
type: feature
blocked-by: []
status: working
created: 2026-08-31
owner: frankD
summary: "Rung 2 of feature-busybox-kiosk-selfhosting-target. FIRST BAR MET 2026-09-01 (2789f87a7): a two-applet busybox (cat+echo+the multiplexer, NUM_APPLETS 2, dispatch table compiled IN) built by pxx is byte-identical to gcc over 28 cases on x86-64 AND aarch64 and agrees with upstream's separately-linked binary; argv[0], `busybox <applet>`, --list, --help, unknown applet and bare busybox all covered. Cost ONE compiler fix: a constant left operand of && / || survived every -O level including -O3 (88ef1232f). Harness is now tools/busybox_diff.sh --applets. STILL OPEN: `ash` (fork/exec/wait, the process model) and the TU surface -- 28 of libbb's ~145, so getpwnam/statfs/getrlimit/getmntent are still untouched."
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

---

## Progress 2026-09-01 (frankD) — first bar MET

Compiler BINARY sha256 `b4ffb6c0caf4…` (the self-host fixedpoint stamp, not a
commit), from commits `88ef1232f` (the fix) and `2789f87a7` (the harness) —
both read off `git log origin/master` after the push, so they are not the
pre-rebase ids the commit messages themselves cite. Reproduce with `tools/busybox_diff.sh`; rung 1 with
`tools/busybox_diff.sh --applets cat`, re-run GREEN.

```
busybox-diff: applets=cat echo  translation units=28
  ORACLE  gcc unity build (28 cases)
  ORACLE  busybox agrees with the gcc unity
  PASS    x86_64   byte-identical to the gcc oracle over 28 cases
  PASS    aarch64  byte-identical to the gcc oracle over 28 cases
```

### What the attempt actually broke on — one thing, and it was not on the list

This ticket's "what rung 1 leaves open" predicted `getpwnam`/`statfs`/
`getrlimit`/`getmntent` and an `__attribute__((section(".rodata.applets")))`
table. **Neither was hit.** busybox 1.36.1 has no `.rodata.applets` anywhere —
the table is plain generated arrays in `include/applet_tables.h` — and cat+echo
reach none of those libc surfaces. The list was a good guess and the attempt
did not need it, which is the point of attempting rather than triaging.

What it did break on was **a constant `&&`/`||` keeping its dropped operand**,
at every optimisation level including `-O3`. Multi-applet turns on two guards a
single-applet build compiles out entirely — `ENABLE_FEATURE_INSTALLER && ...`
around `xmalloc_readlink`, and `(0 || 0 || !BB_MMU)` around `re_execed_comm` —
and neither function is linked in that configuration, so the binary died before
`main` with `symbol lookup error`. Fixed in `cparser.inc`; the residual
dead-ARM half at `-O0` belongs to
[[feature-a-fold-the-consensus-dead-branch-core-at-every-level]], whose summary
was corrected in the same batch (it claimed `-O1/-O2/-O3: fine`, which was false
for exactly this shape).

**Not wired as a blocker of [[umbrella-compile-and-run-dosbox]]**, deliberately:
the remaining half only bites at `-O0`, and nothing builds at `-O0`. Wiring it
would put a row in the umbrella that does not block.

### What is still open, and what it will cost

1. **`ash`** — the second bar, and the ticket is right that it is its own job:
   `fork`/`exec`/`wait` is a process model, not an applet.
2. **The TU surface.** 28 of ~145. Two applets that both live in `coreutils/`
   and neither of which forks is a narrow slice; the honest next step before
   `ash` is a WIDER applet set (`ls`, `mkdir`, `cp`, `grep`, `sed`) which is
   where `getpwnam`/`getgrgid`/`statfs` actually arrive. `--applets` takes them
   already; each is a `CONFIG_<NAME>` in `allnoconfig`.

### Harness notes for whoever takes it next

`tools/busybox_diff.sh` generates its unity from `busybox_unstripped.map` and
reads the preamble out of `tools/busybox_cat_unity.c`, which is now also the
positive control for the single-applet case. Adding an applet should need no
harness edit at all — if it does, that is the finding.

Two dead mechanisms were found in the old harness and fixed: `BB_VER` was read
from `include/bb_config.h`, a header busybox has never had (so rung 1 built
with the hardcoded tag throughout), and the case counter printed
`PASS ... over 0 cases` because one case cats 4KB of `/dev/urandom` and grep
switched to binary mode. A zero case count is now a hard failure.

---

## Progress 2026-09-01 part 2 (frankD) — the SEPARATE-COMPILATION attempt

The first bar was met with a UNITY build, which is how rung 1 worked too. The
honest next step was a wider applet set, and it broke the model rather than the
compiler: **at seven applets gcc itself cannot build the unity.** Each busybox
applet defines its own `struct globals` and `include/common_bufsiz.h`
redeclares its enum, both fine across separate translation units and both
collisions in one. The harness reported no result, correctly — there was no
oracle, so "no differences" would have been true and worthless.

So the attempt moved to busybox's OWN build model: 52 translation units of a
seven-applet configuration (`cat echo ls mkdir cp grep sed`), compiled one at a
time with `--emit-obj` and busybox's real command line. **51 of 52 now
compile.** Six defects, in the order the attempt hit them:

| | what | where it was fixed |
| --- | --- | --- |
| 1 | `-include <file>` did not exist — on every one of busybox's ~145 TUs | `ef937b2f9` |
| 2 | `, ##__VA_ARGS__` comma deletion not implemented — `ls`, `mkdir` | `ef937b2f9` |
| 3 | a directive INSIDE a macro argument list abandoned the call — `mkdir` | `ef937b2f9` |
| 4 | an absolute path in `#include "..."` was never resolved | `ef937b2f9` |
| 5 | crtl had no `lchown`, then no `mknod`, then no `truncate` | `d86bb32fe`, `ca918c6ab` |
| 6 | **objects carry no DATA symbols** | filed, not fixed |

Note the shape of 1-4: **four preprocessor defects, and the first one hid the
other three.** Nothing could compile at all until `-include` existed, so the
"busybox needs N compiler fixes" estimate could not have been made by reading
the backlog — only by running the build.

### The wall, and it is one thing

[[bug-a-an-object-neither-exports-nor-imports-data-symbols-and-links-silently-wrong]],
wired to [[umbrella-compile-and-run-dosbox]]. A pxx object exports no `OBJECT`
symbols and turns `extern int x;` into a local `.bss` slot rather than an
undefined import, so **two pxx objects sharing a global link cleanly and read
different memory** — measured, printing `0` where gcc prints `99`, with no
diagnostic from compiler or linker.

That is why the one TU that fails is `libbb/ptr_to_globals.c`, whose entire
content is one global pointer, and why the other 51 cannot be linked either.
`elfwriter.inc`'s object writer is under active work by frankA/frankC, so it is
filed with the measurement rather than half-fixed in parallel.

### Also found, not on this path

[[bug-a-i386-c-main-gets-argc-and-argv-swapped]] — a C `main` on `--target=i386`
gets `argv = 0x3` (the real `argc`) and `argc` = a garbled pointer. Pascal's
`ParamCount` on the same target is correct, so it is the C entry bridge.
Surfaced because the crtl tests above were run on every runnable target, which
is the only reason anything looked at i386 argument passing at all. Wired to
[[umbrella-cross-target-codegen-is-correct]].

### State of the two bars

- **Bar 1, multi-applet dispatch: MET**, and repeatable at `tools/busybox_diff.sh`.
- **Bar 2, `ash`: not started, and it is now behind the linker.** `ash` is a
  shell: it forks, execs and waits, and it is far past the size where a unity
  build is available as a workaround. Whoever takes it should expect to need
  the data-symbol work first, rather than discovering it a second time.
