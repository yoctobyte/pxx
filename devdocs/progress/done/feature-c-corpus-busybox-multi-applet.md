---
slug: feature-c-corpus-busybox-multi-applet
title: "busybox beyond cat: the multi-applet binary, and ash"
track: C
prio: 70
type: feature
blocked-by: []
status: done
created: 2026-08-31
owner: frankD
summary: "Rung 2 of feature-busybox-kiosk-selfhosting-target. BOTH BARS MET 2026-09-01. First bar (2789f87a7): a two-applet busybox byte-identical to gcc over 28 cases on x86-64 AND aarch64, agreeing with upstream'''s separately-linked binary. SECOND BAR (ash) MET: tools/busybox_diff.sh --applets '''cat echo ash''' is GREEN -- the 41-TU ash unity is byte-identical to the gcc oracle over 62 cases on x86-64 AND aarch64, and the gcc unity agrees with upstream'''s own build. FIFTEEN defects were named and closed getting there, every one found by ATTEMPTING the target rather than by triaging the backlog: a C frontend parse bug (struct-typed local with a fn-pointer member); crtl'''s whole missing shell surface (fnmatch, full signal set + NSIG, strsignal, _SC_CLK_TCK, times, uname, pwd/getpwnam, a real execvp over a new execve, NAME_MAX/PATH_MAX, dprintf/vdprintf, getrlimit/setrlimit); a clock_t that was `long long` where glibc has `long`; crtl'''s own implementation being preprocessed in the PROGRAM'''s macro environment, and then the OPPOSITE error where crtl could not see its OWN header'''s macros; printf %m emitted verbatim, which blanked the reason on every busybox error at once; fork/vfork/wait/waitpid stubbed because a PAL entry issuing SYS_fork was NAMED PalVfork and three comments reasoned from the name; a compiler SEGFAULT with no diagnostic at -O0/-O1 (AN_PTR_CAST overloads ASTRight as a proc-signature index, not a child); sizeof(**p) answering the pointer size; a `**` declarator losing its pointee record unless it was FIRST in its declaration; pointer-minus-pointer tagged as a pointer so the next operator scaled (OPTIND became 9, getopts spun forever, hanging the harness twice for 39 and 22 minutes); and `void *` arithmetic scaling by FOUR (ash builds on `stackblock() + n`, uncast, beside a cast sibling that was always right). STILL OPEN, not blocking this ticket: the unity cannot host ash and coreutils/test.c together in EITHER order, measured, so the `[` builtin needs separate compilation -- bug-a-an-object-neither-exports-nor-imports-data-symbols."
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


## 2026-09-01 — bar 2 (ash): eight defects, named by attempting, not by triage

The instruction was to attempt the target and let each failure name a ticket.
That is what happened; none of these came from reading the backlog, and the
ORDER is the finding, because the first one hid the rest.

**Where it stands.** `tools/busybox_diff.sh --applets "cat echo ash"` configures
a 41-TU ash unity, gcc builds it, the gcc unity agrees with upstream's
separately-linked binary over 62 cases, and pxx now compiles through everything
below and stops at `getpwnam`. Not green yet. What is listed as fixed is fixed
and tested; what is listed as a ceiling is measured.

### Compiler (Track C, landed)

1. **A local whose type is a struct with a function-pointer member did not
   parse.** `ParseCDeclType` records an inline fn-pointer declarator's name in
   `CTypeFnPtrName`; a struct BODY containing `int (*f)(int)` sets it from the
   MEMBER declarator and leaves it set. `ParseCGlobalVarDecl` has guarded
   against exactly that with `baseTk = tyPointer` for a while, with a comment
   naming the shape. `ParseCLocalDeclAST` never got it. Boundary measured before
   fixing: named struct works, anonymous fails, array or not — so the trigger is
   the leftover global, not the anonymity. `test/c_struct_fnptr_member_local.c`
   pins both arms. Found by fnmatch's `[:class:]` table.

2. **crtl's own implementation was preprocessed in the PROGRAM's macro
   environment.** busybox's `libbb.h` poisons the whole ctype family and
   `#define isprint(a) isprint_is_ambiguous_dont_use(a)` reached
   `lib/crtl/src/fnmatch.c`'s own `isprint`. Eight lines reproduce it; gcc
   compiles it and pxx did not. A libc shipped as SOURCE is still a separate
   translation unit — gcc's is immune only because it is already compiled, so
   this hazard is structural to pxx and invisible until a program redefines a
   name crtl uses.

   **The first fix hid too much, and that is the part worth reading.** Hiding
   `_GNU_SOURCE` made crtl's `<string.h>` skip its guarded forward to
   `<strings.h>`; the header is include-guarded, so the narrower decision became
   PERMANENT and the program's own later include expanded to nothing —
   `strncasecmp` undeclared in the PROGRAM, two files from the change, as a
   missing function rather than as a macro problem. Rule now: the
   implementation's RESERVED namespace (leading `_`, plus `NDEBUG`) stays
   visible, because that namespace is the channel a program configures the
   implementation through; ordinary identifiers are the program's and are hidden.

### crtl (Track C, landed)

3. **No `fnmatch.h` at all** — a HARD error when cross-compiling, so ash could
   not be built for aarch64; on x86-64 it silently resolved from `/usr/include`.
   Compared against glibc over a flag MATRIX, not a list, because `FNM_PATHNAME`
   and `FNM_PERIOD` interact. Two defects it caught that reasoning did not: a
   trailing backslash is POSIX-undefined and glibc never matches it, and
   `FNM_CASEFOLD` folds literals and ranges but NOT `[:class:]`.
4. **`signal.h` had 11 signals** — full asm-generic set plus `NSIG`, which a
   shell sizes its trap table with.
5. **`strsignal`** — glibc's exact strings, because a shell PRINTS them.
6. **`_SC_CLK_TCK`** — a shell divides by it, so a wrong value is a plausible
   wrong number rather than a failure.
7. **`times(2)`** and **`uname(2)`** through the five PAL layers.
8. **`clock_t` was `long long` where glibc has `long`.** The one to remember:
   same width on x86-64 and aarch64, different on i386, arm32, riscv32 and
   xtensa. `struct tms` is filled by the KERNEL and ash reads it as
   `*(clock_t *)((char *)&buf + offset)` — by byte offset, through clock_t — so
   a too-wide clock_t reads two fields as one, silently, on every 32-bit target.
   Right where we test, wrong everywhere else. Sizes AND offsets now asserted.

### The ceiling, measured — this is the part that is not mine to fix

**The unity build cannot host `ash` and `coreutils/test.c` together, in EITHER
order.** Both reach their globals through the same macro pattern over ordinary
identifiers — ash 43 of them, test.c 6 — and they collide both ways:

```
test.c first : ./coreutils/test.c:441 #define args (S.args)
               breaks ash.c:12025  `union node *args, **app;'
ash.c  first : ./shell/ash.c:495    #define arg0 (G_misc.arg0)
               breaks test.c:897
```

No include order satisfies both, so `ASH_TEST` is off and the shell cases use
`case $((expr)) in` instead of `[`. This is the first thing rung 2 wants that
**separate compilation is REQUIRED for rather than merely tidier** — a second
argument for [[bug-a-an-object-neither-exports-nor-imports-data-symbols-and-links-silently-wrong]],
reached from the frontend end while that ticket is worked from the writer end.
`shell/ash.c` must also come LAST in the unity for the same underlying reason
(its macros leak forward into `coreutils/echo.c`'s local `eflag`), which is
handled and asserted, but ordering cannot save the pair above.

### Harness defects fixed on the way — all one family

Three, and each was a cheap question that was correct about something else:

- **"Already configured?" asked only the applet COUNT.** A tree with the right
  applets and every ash feature OFF was accepted and the reconfigure skipped —
  every `$((arith))` case would have been a syntax error in BOTH builds and the
  run GREEN over a shell that cannot do arithmetic. One list now drives the
  configure and the check, including what is deliberately off, because
  `ASH_TEST=y` is exactly as wrong as `FEATURE_SH_MATH=n`.
- **The banner carries `AUTOCONF_TIMESTAMP`**, stamped at CONFIGURE time, and
  busybox does not rebuild the world when only that moves. Measured:
  `autoconf.h` 19:09:43, busybox relinked 19:09:53, `libbb/messages.o` still
  18:59:14 carrying the OLDER banner. Pinned in the unity, normalised in the
  upstream cross-check only, with a control that the normaliser fired.
  **Bar 1 passing this check was luck** — it matched only because both builds
  happened to share an `autoconf.h` vintage.
- **`shell/ash.c` must be ordered last**, as above.

### Next

`pwd.h` / `getpwnam` (ash's `~user` expansion). Then re-run and find the next one.

## 2026-09-01 — second bar met: `ash`

```
busybox-diff: applets=cat echo ash  translation units=41
  ORACLE  gcc unity build (62 cases)
  ORACLE  busybox agrees with the gcc unity
  PASS    x86_64   byte-identical to the gcc oracle over 62 cases
  PASS    aarch64  byte-identical to the gcc oracle over 62 cases
busybox-diff: GREEN
```

compiler sha256 `ea6833440ff8`, commit `52ad546b9` + the void-pointer fix.

**Every defect on this list was found by ATTEMPTING THE TARGET.** None came
from reading the backlog, and the order they appeared in is the order they
actually block real-world usage — which is the point of growing an umbrella by
attempt rather than by triage.

Three of them are worth re-reading later because of HOW they hid, not what
they were:

- **`printf %m` emitted verbatim.** busybox writes essentially every
  errno-carrying diagnostic through `bb_perror_msg`, so one missing conversion
  blanked the reason on *every* failure in the corpus simultaneously. `can't
  fork: %m` was hiding `ENOSYS`, a completely different investigation. Fixing
  the instrument came first, and that ordering repeated twice more.
- **The `-O0` compiler segfault.** `-O0` was the discriminator I wanted for a
  *different* bug, and the instrument itself was broken. Same ordering again.
- **`ptr - ptr` tagged as a pointer.** My first hypothesis was that the
  subtraction returned an unscaled byte difference; I wrote a six-shape probe
  to prove it and every row passed. It could not have found the bug, because
  the subtraction was never the broken part — its RESULT TYPE was, so the
  defect only appears once a SECOND operator consumes the difference.
  Instrumenting ash's own `getopts` and seeing `diff=1` and `ind=9` printed
  from the same expression is what named it.

**Two hangs, 39 and 22 minutes, both with no output at all.** Both were
`getopts` spinning on an `OPTIND` that never advanced. A wrong value in a loop
condition presents as a hang, not as a wrong answer, and there is nothing to
read while it happens — worth remembering the next time this harness stops
producing output rather than failing.

### What is NOT established by this

- `ash` is built into the unity; it is not proven against a real interactive
  session, only the 62 scripted cases.
- The `[` builtin is still out (`ASH_TEST=n`): ash and `coreutils/test.c`
  cannot coexist in the unity in EITHER order, measured both ways. That is the
  unity model's ceiling, not a pxx defect, and it is a second independent
  argument for `bug-a-an-object-neither-exports-nor-imports-data-symbols`.
- LINUX ONLY, x86-64 and aarch64. Nothing here says anything about i386 or
  arm32, where `feature-a-crtl-is-not-large-file-safe-at-ilp32` and
  `bug-a-the-pin-cannot-build-any-c-program-for-i386-or-arm32` are both open.

## 2026-09-01, later — separate compilation, and what it retires

Rung 2's bars were met on the unity. The unity is not the interesting build
model, and two things changed on the same day that make it worth leaving
behind.

**First, a correction, because I logged the opposite and it was wrong.** I
reported that the unity could not hold a fourth applet — *any* fourth applet —
on twelve identical failures. It can. Nine of the twelve build fine
(`mkdir rm cp mv pwd wc head sleep printf`). The twelve identical failures were
one applet measured twelve times: `busybox_diff.sh`'s "is the tree already
configured?" test asked the applet COUNT and the ash knobs and never asked
WHICH applets, so every `cat echo ash <X>` matched the tree the first iteration
had built. Fixed in `e20a2ca56`, with a positive control in both directions.
The tell was there before the check: twelve *byte-identical* error texts is not
what twelve independent measurements look like.

What is true about the unity is narrower and still real. Three separate files
break it, all the same way — a file that assumes it owns its namespace:

| file | what it claims | who it breaks |
| --- | --- | --- |
| `include/common_bufsiz.h` | `enum { COMMON_BUFSIZE = 1024 }`, no include guard | `ls`, `tail` |
| `shell/ash.c` | 40 `#define`s of ordinary names (`optlist`, `eflag`) | whatever follows it |
| `coreutils/uname.c:112` | `#define options "snrvmpioa"` | whatever follows it |
| `coreutils/test.c` | globals macros over ordinary identifiers | `ash`, in BOTH orders |

The harness orders around the second, refuses the fourth, and cannot do
anything about the first or third. None of them is a pxx defect and gcc rejects
the unity too.

**Second: separate compilation now works**, which makes every row of that table
moot rather than ordered around. It became attemptable when frankA landed
[[bug-a-an-object-neither-exports-nor-imports-data-symbols-and-links-silently-wrong]],
and attempting it named exactly one compiler defect — `x & 0` never folded to a
literal, so a constant-false branch kept its dead arm and
`make_human_readable_str` became a real external reference in `coreutils/ls.c`
(`3056e214c`). That was the ONLY undefined symbol across all 41 units.

`tools/busybox_diff.sh --separate` is the mode. x86_64 only, because
`--emit-obj` has no aarch64 object writer yet. It still needs `-Wl,-z,muldefs`
for [[bug-a-every-object-defines-the-whole-of-crtl-globally-so-no-two-objects-link]],
which is now the one thing between pxx and separately compiling a real C
project.

## 2026-09-01, later still — twelve applets, both targets

```
busybox-diff: applets=cat echo ash mkdir rm cp mv pwd wc head sleep printf
              translation units=61
  ORACLE  gcc unity build (114 cases)
  ORACLE  busybox agrees with the gcc unity
  PASS    x86_64   byte-identical to the gcc oracle over 114 cases
  PASS    aarch64  byte-identical to the gcc oracle over 114 cases
busybox-diff: GREEN
```

compiler sha256 `825c28a30c31`. **Zero new defects** — the fifteen closed
getting to three applets covered the next nine.

`run_coreutils_cases` is new and carries the constraint that matters for file
tools: everything runs under `$D`, which oracle and subject SHARE. Each binary
is installed in its own directory, so a path printed from the install dir would
diff on every row for no reason — and paths in error messages are half of what
is being compared, since that is where errno reaches the output. Nothing
timestamp-, uid- or device-sensitive: no `cp -a`, no `-p`. The last row prints
the resulting tree, which catches a tool that reported success and did nothing —
something no other row would notice.

### What this rung does NOT establish

- Twelve applets, not the ~145 a real userland has. `ls`, `tail` and `uname`
  are still out, and all three are unity-model limits (see the table above),
  not pxx defects.
- x86-64 and aarch64, Linux. Nothing here says anything about i386 or arm32.
- The scripted cases only. `ash` is not proven against an interactive session.

## Log
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
