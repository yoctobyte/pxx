---
track: C
prio: 78
type: feature
status: working
blocked-by: []
owner: frankC
summary: "OWNER-SET TARGET 2026-08-30 -- rung 1 of feature-busybox-kiosk-selfhosting-target, re-priced 60->78 to match. UNBLOCKED: libbb.h compiles and the 145 TUs are REACHABLE (the preprocessor no longer dies); it does NOT link yet, and the residue is busybox's own libbb symbols. crtl getopt landed 2026-08-30. Build ONE busybox applet -- cat -- standalone, skipping the CONFIG_* maze. Success = pxx-built `cat` byte-identical output to a gcc-built one across a fixed input set, under tools/run_target.sh on x86-64 + aarch64."
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

## 2026-08-31 — the 20-TU closure is down to TWO undefined, both busybox's own

`app.c` (coreutils/cat.c + 19 libbb TUs + a `main` calling `cat_main`) now
compiles with:

```
warning: crtl does not define string_array_len, bb_show_usage
```

`string_array_len` is `libbb/compare_string_array.c`, a TU the real build links
and this closure has simply not added yet. `bb_show_usage` is in
`libbb/appletlib.c`, which the closure excludes on purpose — it carries the
applet table, and that table names `ash_main`.

Everything else on that list closed this session. **The libc side is now empty.**

### What actually closed it, and neither was a missing libc function

`opendir/readdir/closedir/rewinddir/fdopendir/dirfd` are real over the PAL's
`PalGetDents64` (`lib/crtl/src/dirent.c`, `__pxx_getdents64` bridged in
`lib/rtl/pxxcio.pas`), byte-identical to a glibc-built binary of the same probe
on x86-64 **and** aarch64. The row that earned its own test: without an eager
first `getdents64`, `opendir()` on a **regular file** succeeded here and failed
with `ENOTDIR` under glibc — a wrong answer a directory walker reads as an
empty directory.

The other five — `xatoll`, `xatoull`, `xstrtoll`, `xstrtoull`, `xatou` — were
never a crtl gap at all. They are busybox's own, defined by
`libbb/xatonum_template.c`, and **two preprocessor bugs were eating exactly the
definitions spelled with an empty macro argument**:

1. **C99 6.10.3p4.** `m()` on a macro that *has* parameters supplies **one**
   argument whose token sequence is empty — not zero arguments. Both argument
   splitters in `cpreproc.inc` (the expander and the `#if` evaluator) counted
   zero, leaving the sole parameter **unbound**, so `#define xatou(rest)
   xatoull##rest` expanded `xatou()` to the literal identifier `xatoullrest`.
   No diagnostic: a plausible name, a definition that silently went missing,
   and a call that would have gone to the system libc at run time.

2. **C99 6.10.3.4p2.** Fixing (1) exposed the second. The `int` instantiation
   spells `#define xstrtou(rest) xstrtou##rest` — a macro expanding to **its own
   name** — and the rescan-across-the-boundary rule then spliced the parameter
   list that followed it, turning `unsigned int xstrtou()(const char *n, int b)`
   into `unsigned int xstrtouconst char *n`. 6.10.3.4p2 says the name of the
   macro being replaced is not replaced, so the splice must be skipped when the
   tail name IS this macro. `CAT(A,B)(x)` is unaffected and is a control row:
   that name came from *pasting*, not from `CAT` itself.

Both were found by *reading the undefined list as evidence rather than as a
shopping list*. The five names were exactly the five `xxx()` empty-argument
forms across the instantiations the config reaches, and nothing else — a
one-to-one match that named the mechanism before any code was read.

## 2026-08-31 (later) — rung 1's x86-64 half is MET

`busybox cat`, built by pxx from upstream unvendored source, produces output
**byte-identical to a gcc-built `busybox_CAT`** across the fixed input set:
empty file, 4 KB binary file, multi-file concat, file with no trailing
newline, `-` mixed with named files, stdin pipe, no args, `-u`, a missing file
alone, a missing file between two good ones, and the same file three times —
including the `cat: can't open '...': No such file or directory` diagnostic
and every exit status.

**It is a real single-applet build, not a hand-picked file list.** `.config`
was reduced with upstream's own `make_single_applets.sh CAT`
(`NUM_APPLETS 1`, `SINGLE_APPLET_MAIN cat_main`), and the pxx unity is the
**exact 25 archive members `ld` pulled** for that link, read off
`busybox_unstripped.map`. Zero undefined symbols. The oracle is the binary
that build produced.

One deviation from the object list, and it is upstream's own switch:
`#define BB_GLOBAL_CONST` (documented at `include/libbb.h:379`). `libbb.h`
declares `ptr_to_globals` const and `libbb/ptr_to_globals.c` re-declares it
writable — which only works while they are separate translation units. **gcc
refuses that combination outright** ("conflicting type qualifiers"); we
accepted it silently and then jumped into hyperspace when `lbb_prepare` wrote
through the const object. Emptying `BB_GLOBAL_CONST` gives the whole unity the
writable object a real link produces.

### Three compiler bugs stood between "links" and "runs", none of them C-frontend-shaped

1. **`alloca()` inside a call's argument list corrupted rsp.** x86-64 restores
   the caller's rsp from a FIXED offset below the outgoing argument area;
   `alloca` moves rsp. `strcpy(alloca(len + 1), applet_opts)`
   (`getopt32.c:373`) left control at `asctime_r + 1019`, three bytes into a
   seven-byte instruction. The frontend now hoists such allocas into a
   temporary evaluated before the call — what gcc does, for the same reason.
   The backend invariant is filed as
   [[bug-a-alloca-inside-a-call-argument-list-corrupts-the-restored-stack-pointer]].

2. **An `extern T name[];` declaration kept its one-element size when the
   definition arrived.** `bkm_suffixes`, `cwbkMG_suffixes` and
   `kmg_i_suffixes` — 128 bytes each — were allocated **eight bytes apart**,
   and `msg_eol`, `logmode` and `xfunc_error_retval` landed inside them.
   `strlen(msg_eol)` then walked a pointer assembled half from a suffix-table
   entry. This is the ordinary way C shares a table through a header, so the
   blast radius is every C program that does it.

3. **`<alloca.h>` resolved from the host** and its declaration made pxx's
   builtin step aside, so the program linked against an `alloca` symbol that
   cannot exist. crtl now carries `alloca.h` with the macro only — which is
   what every compilation of glibc's header actually uses.

Also landed: crtl `<malloc.h>` + `mallopt` (a truthful `return 0`: our
allocator has no trim threshold to set).

### The aarch64 half is BLOCKED, and not on anything C

Two things, in this order:

- **`IR_ALLOCA` is x86-64 only.** `--target=aarch64` refuses outright:
  `target aarch64: IR op not yet supported: alloca`. busybox uses `alloca`
  unconditionally in `getopt32.c`, so no applet builds for any cross target
  until the op is ported. Track A, and whatever lands there must not repeat
  the fixed-offset restore that bug (1) came from.
- **The cross targets get no host-header fallback** (correctly — `/usr/include`
  is x86-64's). The x86-64 build silently resolved `byteswap.h`,
  `sys/param.h`, `endian.h`, `pwd.h`, `grp.h`, `mntent.h`, `paths.h`,
  `sys/statfs.h` and friends from the host; aarch64 stops at the first one.
  That is crtl surface to write, mechanical but real — and note it means the
  x86-64 result above leans on host headers for those declarations.
