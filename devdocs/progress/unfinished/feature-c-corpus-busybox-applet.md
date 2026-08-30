---
track: C
prio: 78
type: feature
status: unfinished
blocked-by: []
owner: 
summary: "OWNER-SET TARGET 2026-08-30 -- rung 1 of feature-busybox-kiosk-selfhosting-target, re-priced 60->78 to match. UNBLOCKED 2026-08-30 -- libbb.h now compiles and all 145 TUs are reachable. Spun out of idea-c-realworld-test-targets (its own top pick, #1 in the suggested order). Build ONE busybox applet -- cat -- from upstream source with cfront, standalone, skipping the CONFIG_* maze. Success = pxx-built `cat` byte-identical output to a gcc-built one across a fixed input set, run under tools/run_target.sh on x86-64 + aarch64. busybox is syscall-heavy, which points it straight at crtl, the layer that is actually thin."
---

# busybox `cat` via cfront — one applet, real syscall load

Concrete target spun out of [[idea-c-realworld-test-targets]] per the
coordinator's split instruction. That idea is a brainstorm parent and ranks
busybox **🟢 top pick, #1 in the suggested order**; this is the ticket that
makes it workable.

## Why busybox and not the other remaining candidates

The idea's suggested order (busybox → tcc → cJSON/stb → DOOM) reads stale
because its 2026-07-19 sweep note marks tcc/cJSON/stb done and says "busybox
declined for ESP". **That decline is ESP-scoped and explicitly not a Track C
decline.** `147f5f5e` says so in its own commit message:

> busybox-ash-via-cfront stays open as a **Linux-only Track C corpus flex**
> (idea-c-realworld-test-targets); we borrow its applet-dispatch pattern, not
> its process model.

and the umbrella it edited keeps "busybox-ash via cfront as a monster Track C
corpus target" open. So the top pick was never actually taken off the table —
only its ESP reading was. Leaving DOOM (the idea rates it "low signal, high
morale"), micropython (a qstr-generation build-system lift before a single line
of C is compiled), and p2c (early-90s K&R C — a *legacy dialect*, not
representative of the real code CLAUDE.md's compat tag ranks by).

The selection rule I was given was **pick the one whose first three failures you
can predict**, because that is the one that produces tickets instead of
yak-shaving. For busybox I can:

1. **Missing crtl syscall surface.** busybox is deliberately syscall-heavy and
   `lib/crtl` is our genuinely thin layer — this is the whole point of the pick.
   Expect gaps in `<sys/stat.h>`, `fadvise`, `open` flag spellings.
2. **GCC attributes on the applet table.** busybox puts applets in a linker
   section (`__attribute__((section(".rodata.applets")))`) and uses
   `ALIGN1`/`FAST_FUNC` macros. Building ONE applet standalone sidesteps the
   table, but the attributes still parse.
3. **The `CONFIG_*` / `autoconf.h` maze.** Mitigated exactly as the idea says —
   do not build the multi-call binary; hand-write a minimal config header.

If those three are what actually happen, the pick was right. If the first
failure is somewhere else, that is more interesting, not less, and it gets its
own ticket in the owning lane.

## Success criterion (stated up front, per the split instruction)

`busybox cat` built by `$(COMPILER)` from **upstream, unvendored** source
produces **byte-identical output to a gcc-built binary of the same source**
across a fixed input set (empty file, binary file, multi-file concat, stdin
pipe, missing file + its exit status), on **x86-64 and aarch64** via
`tools/run_target.sh`.

Note the claims discipline: that is **behavioral parity of the program's
output** against a gcc-built oracle — the zlib-row claim, NOT the self-host
fixedpoint row. Do not write it up as "byte-identical to gcc".

Anything short of the full criterion lands as: the applet that DOES work, plus
a ticket per gap **in the owning lane** (crtl gap → B, codegen/ABI → A,
C parsing → C).

## Acquisition — pinned, gitignored, never vendored

Follows the existing pattern exactly (`tools/install_lib_candidates.sh`:
third-party source never lives in the repo, only the tool that fetches it;
pinned to an upstream commit with a PROVENANCE.md). Upstream
`https://git.busybox.net/busybox` is reachable from this box (verified
2026-08-30).

**`library_candidates/` is currently EMPTY on this box** — every C corpus tree
is missing, so `test-tcc` / `test-cjson` / `test-quickjs` self-skip and report
pass over nothing. That is
[[task-t-the-c-corpus-is-two-rungs-not-four-and-a-missing-tree-reports-pass]]
and it is Track T's, not this ticket's; noted here because it means there is no
warm corpus baseline to lean on and the fetch is step one.

## Gate

`make compiler/pascal26` (the fixedpoint) + the criterion above. Breadth is
Track T's, swept against the pushed sha — this ticket does not run a full suite.

## SESSION 1 RESULT — fetched, configured, oracle green, BLOCKED at TU #1

Upstream busybox **1.36.1**, sha `1a64f6a20aaf6ea4dbba68bbfa8cc1ab7e5c57c4`,
cloned into gitignored `library_candidates/busybox` (guard checked: `git
check-ignore` confirms the dir is ignored before fetching, same invariant
`install_lib_candidates.sh` enforces). Nothing vendored.

`make allnoconfig` + `CONFIG_CAT=y`. **The gcc oracle builds clean and works** —
75888-byte binary, `busybox cat` correct, rc=0. So the oracle side of the
criterion is already in place.

**All three of my predicted first failures were wrong.** It is not a crtl gap,
not the applet-table attributes, not the CONFIG maze. The first failure is a
**compiler capacity limit** that stops the build before any busybox code is
parsed:

```
pascal26:1: error: C include nesting too deep
              (the preprocessor has 16 include buffers; this include is at level 17)
```

Repro is four lines and does not need `cat.c` at all — `libbb.h` by itself does
it. Since every applet includes `libbb.h`, this blocks **all 145 TUs** of a
cat-only build, so there is no smaller starting point to retreat to.

I said when filing that a first failure somewhere unexpected would be "more
interesting, not less". It is: a prediction about the thin layer (crtl) was
answered by the preprocessor, which nobody was watching, and it was found by the
first real aggregation header pointed at it.

**Blocked on Track A** —
[[bug-a-c-preprocessor-include-buffers-are-sixteen-globals-not-an-array]].
The buffers are `CPrepInclude0..15` in `compiler/defs.inc:3765`, A's shared
file; Track C may not edit it. The `blocked-by` edge above propagates this
ticket's p60 down to that p40 refactor, which the evidence there argues is
mis-typed as tidiness.

The two `case depth of 0..15` ladders in `cpreproc.inc` are Track C's and are
mechanical to convert once the storage is an array — I will do that half and
resume here.

### What is already banked for the resume

- Tree fetched and configured; oracle binary built and verified.
- The TU set is enumerated: 145 objects, list method in this session
  (`find . -name '*.o' -newer .config`). Note it includes `shell/ash.o` and
  x86-64 SHA files, so "one applet" is not one file even at allnoconfig.
- The build shape is settled: pxx has **no `-c`** on x86-64 and no `-D`/`-include`
  flags, so this follows `test/lua/runner.c` — a **unity `.c`** that `#define`s
  `_GNU_SOURCE`/`BB_VER`/`KBUILD_*`, includes `autoconf.h`, then the TUs, built
  with `-I` roots. That pattern is proven by the lua corpus and needs no new
  compiler flags.

## Parked 2026-08-30

blocked at TU 1 by the 16-deep C preprocessor include cap (bug-a-c-preprocessor-include-buffers-are-sixteen-globals-not-an-array); libbb.h alone hits level 17, so all 145 TUs are blocked. Buffers live in defs.inc = Track A, not C's to fix. Tree fetched + gcc oracle green and verified.

**Before resuming:** read the reason above, then the ticket body. If the reason does not tell you what would make this worth picking up again, establishing that is the first step -- a park is a handoff to a stranger who may be you.

## UNBLOCKED — 2026-08-30, and the blocker was neither of the two named here

`libbb.h` compiles. The wall was **not** the 16-buffer cap: raising it to 128
moved the error from level 17 to level 129 and fixed nothing, because the depth
was tracking the cap rather than any real nesting. One header was including
**itself**.

`/usr/include/sys/signal.h` is one line, `#include <signal.h>`, and the C
preprocessor searched the including file's own directory for **angled** includes
as well as quoted ones — so that resolved back to itself and recursed until the
buffers ran out. C 6.10.2 gives the including file's directory to `"..."` only.
Fixed in `1672aeaad`
([[bug-c-the-preprocessor-runs-away-on-sys-param-h-resolved-from-the-host-fallback]]);
[[bug-a-c-preprocessor-include-buffers-are-sixteen-globals-not-an-array]] landed
on its own merits and was never busybox's blocker.

**Where the build stands now**, `autoconf.h` + `libbb.h` + a trivial `main`:

```
warning: crtl does not define xzalloc, xstrtoull_range_sfx, xstrtoull_range,
  xstrtoull_sfx, xstrtoull, xatoull_range_sfx, xatoull_range, xatoull_sfx,
  xatoull, xstrtoll_range_sfx, xstrtoll_range, xstrtoll, xatoll_range_sfx,
  xatoll_range, xatoll, xatou, BUG_xatou32_unimplemented, bb_strtoull,
  bb_strtoll, bb_strtou, BUG_bb_strtou32_unimplemented, bb_strtoi
ok: [code=265896B  data=13772B  bss=68136B  procs=1381]
```

Those are busybox's OWN functions (`libbb/`), not crtl gaps — they resolve once
the `libbb` TUs are actually compiled and linked in. So the next step is the one
this ticket was filed to do: compile the TU set, not fight the preprocessor.

**The filing note that turned out to be right:** *"a first failure somewhere
unexpected would be more interesting, not less."* It was the preprocessor twice
over — once as the reported symptom and once as the real cause, which was a
different mechanism in the same file.
