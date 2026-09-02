---
slug: feature-c-crtl-posix-regex-regcomp-regexec
title: "crtl has no <regex.h>, and it is the single biggest thing between busybox and a self-contained i386 build"
track: C
prio: 60
type: feature
status: done
created: 2026-09-02
found-by: frankD
owner: frankD
blocked-by:
summary: "LANDED. `lib/crtl/include/regex.h` and `lib/crtl/src/regex.c` -- a backtracking VM whose accept instruction records-and-fails so match[0] is leftmost-LONGEST, with a memo that makes a back-reference-free pattern polynomial and is switched off (unsound) when a back-reference appears, and a step budget that returns REG_ESPACE rather than a wrong REG_NOMATCH. BRE and ERE, classes, intervals, back-references, REG_ICASE / NEWLINE / NOTBOL / NOTEOL / NOSUB / STARTEND, and the GNU \\< \\> \\b \\w operators real patterns use. Verified against this box's glibc with the same source built by gcc: 4527 corpus cases from busybox's own sed/grep/awk testsuites and 375 back-reference cases are byte-identical, and 79 of 81 hand-written rows; the two that differ are recorded at the row. **ALL SEVEN translation units this ticket named now become i386 objects** -- libbb/xregcomp.c, awk, sed, grep, expr, test and mdev."
---

# What is missing

`regcomp`, `regexec`, `regerror`, `regfree`, `regex_t`, `regmatch_t`, and the
`REG_*` flag and error constants. busybox reaches them through
`libbb/xregcomp.c`, which every regex-using applet then calls.

The seven translation units, from a full `--emit-obj --target=i386` sweep of the
396 TUs in busybox's own link map (2026-09-02):

| TU | what it needs regex for |
| --- | --- |
| `libbb/xregcomp.c` | the wrapper every other one uses |
| `editors/awk.c` | `~` and `!~`, and field splitting |
| `editors/sed.c` | addresses and `s///` |
| `findutils/grep.c` | the whole program |
| `coreutils/expr.c` | the `:` operator |
| `coreutils/test.c` | `=~` |
| `util-linux/mdev.c` | device-name matching in mdev.conf |

# Why this is not another header

The fifteen headers landed in `eac7126f1` are numbers and structs: the work is
transcribing them from a real header and diffing every value against it. This
one is an ENGINE. What has to be right:

- **BRE and ERE are different languages**, selected by `REG_EXTENDED`, and the
  differences are not cosmetic: in BRE `\(`, `\{` and `\|` are the operators
  and the bare characters are literal, while in ERE it is the other way round.
  sed and grep use BRE by default; awk is always ERE. Getting the default
  backwards does not fail -- it silently treats a pattern's parentheses as
  literal text and matches nothing, or matches everything.
- **POSIX is leftmost-LONGEST, not leftmost-first.** A backtracking engine
  written the Perl way returns the first alternative that matches rather than
  the longest, so `a|ab` against "ab" gives a one-character match. Every
  `s///` that uses alternation then replaces the wrong span, and the output is
  a plausible wrong file.
- `REG_NOTBOL` / `REG_NOTEOL`, which sed needs to iterate `s///g` correctly:
  without them the second and later iterations think they are at the start of
  a line and `^` matches in the middle of one.
- Back-references (`\1`) in BRE, which are what stop this being a clean DFA.
- Character classes (`[[:alpha:]]`), ranges, and equivalence-class syntax at
  least far enough to reject what it cannot do rather than mis-parse it.

# The oracle exists

`tools/gcc_diff_probe.sh` compares against glibc directly, and busybox's own
test suite exercises sed and grep hard. So this is a case where the expensive
part -- knowing whether the engine is right -- is already paid for: write it,
then run every pattern in busybox's `testsuite/sed.tests` and
`testsuite/grep.tests` through both and diff. A regex engine that passes those
is not proven correct, but it is proven not-obviously-wrong on real patterns,
which is the bar rung 5 needs.

# Scope note

`nftw`, `fnmatch` and `glob` are NOT this ticket even though they rhyme;
`fnmatch` is already in crtl and is a different (much smaller) language.

`feature-c-corpus-busybox-i386-the-second-architecture` is what this unblocks.


# 2026-09-02, evening -- what landed, and what the tests can and cannot see

`lib/crtl/include/regex.h` (constants and types measured against this box's
glibc; `regoff_t` is `int` on BOTH widths, `regmatch_t` is 8 bytes) and
`lib/crtl/src/regex.c` (~790 lines). `struct re_pattern_buffer` is deliberately
not glibc's: `re_nsub` is the only field POSIX exposes, and the rest is
crtl-private. The GNU surface (`re_search`, `struct re_registers`) is absent on
purpose -- `CONFIG_EXTRA_COMPAT` and `CONFIG_FEATURE_VI_REGEX_SEARCH` are both
OFF in the busybox config, and declaring a function nobody implements turns a
missing-header error into a link error further away from the cause.

## The engine

A recursive-descent parser emitting a three-field instruction array, then a
backtracking interpreter. Three decisions, each with a row in the test that
fails if it is reversed:

- **The accept does not accept.** `RXI_MATCH` records the end if it beats the
  best so far and then returns FAILURE, forcing the remaining alternatives to
  be explored. That is the whole of leftmost-longest, and without it `a|ab`
  against "ab" gives 1 rather than 2.
- **The memo is off for back-references.** `(pc, pos) already explored` is
  sound only while captures cannot change what matches. It is cleared once per
  `regexec`, not once per start position -- an entry cannot suppress a match a
  later start would have found, because a start that matched returned.
- **The budget returns `REG_ESPACE`.** Not `REG_NOMATCH`: "I ran out of room"
  and "this does not match" are different answers, and reporting the second
  makes grep silently drop a line.

## What the corpus proved, and what it did not

The obvious test was the one this ticket asked for: 147 patterns harvested from
busybox's own `sed.tests`, `grep.tests` and `awk.tests`, 31 subjects, 4527
cases, every one byte-identical to glibc. Then the same corpus was run against
17 deliberately broken engines, and **the leftmost-longest mutation and the
greedy/lazy branch-order mutation each changed ZERO of the 4527 rows.** Real
busybox patterns do not distinguish the rule this engine is built around.

A test that passes on real input and cannot see the central decision is a
breadth check, not a correctness one. So the in-tree test is the hand-written
81-row probe instead, chosen so each row is the only one that fails for some
specific way of being wrong; the corpus stays as the breadth instrument and the
mutation matrix is the record of what each can see. Sixteen of the seventeen
mutations are now caught. Of the two that were not:

- deleting the memo's `memset` was invisible because a fresh `malloc` on this
  box returns zeroed pages. Fixed by construction -- `calloc`, so there is no
  clearing step left to delete.
- turning `REG_ESPACE` into `REG_NOMATCH` was invisible because nothing in
  4527 real cases reaches a 20-million-step budget. Fixed by adding a row that
  does: 200 `a`s against four nested starred groups and their back-references
  trips it in ~0.5s. glibc cannot run that row at all, which is why the test
  carries its own expectations rather than being a gcc diff.

## Four bugs the differential found, none of which crashed

All four produced plausible wrong spans, and three were in the same 40 lines of
code motion:

1. `rx_insert` relocated the instruction it had just written, moving a `*`
   loop's exit two past its own end.
2. `rx_alt` pointed the second branch one instruction short of where it emitted
   it.
3. `rx_interval` copied a body its own edits were moving; `{0,m}` rewound to
   the body's start and then read the instructions it was overwriting.
4. `rx_rep_ok_here` -- the BRE rule that `*` is literal where there is nothing
   to repeat -- compared the atom's start against the BRANCH start, so it also
   refused the star on the FIRST piece of a branch, where the atom is present.
   `\(a*\)b` quietly became four literals. **Nothing caught it because every
   star row in the probe was ERE**; the row that catches it is B13.

# The frontier this moves to

**All seven build.** `libbb/xregcomp.c`, `editors/awk.c`, `editors/sed.c`,
`findutils/grep.c`, `coreutils/expr.c`, `coreutils/test.c` and
`util-linux/mdev.c` each become an i386 object, run individually.

## THE THREE `REMAINING BLOCKERS' FIRST REPORTED HERE WERE MY OWN MISSING FLAGS

The first version of this section said four of seven, and named `strncasecmp`
for awk and busybox's `IF_FEATURE_*()` macros for grep and mdev. Both were
artifacts of the sweep script, not of pxx, and the second one is worth keeping
because of how convincing it was.

busybox's real build FORCE-INCLUDES its config: `Makefile.flags` carries
`-include include/autoconf.h`, and **no busybox header includes it**. Compile
without that flag and every one of the ~2500 `IF_FEATURE_XXX(...)` macros is
undefined, so each invocation survives into the parser as an identifier
followed by a parenthesised expression. The diagnostics that produces are
entirely plausible compiler bugs:

- `stray token at top level (not a declaration): 'IF_DESKTOP'`
- `expected ')' before 'IF_FEATURE_GREP_CONTEXT'`
- `undeclared identifier 'size_t' used as value (treated as 0)`

Three different messages, three different files, all reading as a macro-expansion
gap in the C frontend. A minimal repro of `#define IF_DESKTOP(...)` followed by
`IF_DESKTOP(long long) int f(void);` compiles correctly, which looked like
evidence the bug was context-dependent rather than evidence the macro was never
defined. `-D_GNU_SOURCE` was missing the same way and produced the awk
`strncasecmp` refusal.

**THE CHECK THAT WOULD HAVE CAUGHT IT IS `WHAT FLAGS DOES THE REAL BUILD
USE'**, asked before believing any refusal from a hand-rolled sweep, and it is
now the first thing to ask of any busybox TU that pxx declines.

A bisect of `libbb.h` also has to be recorded as a NON-result: truncating the
header and asking whether the marker survived produced an answer at every step,
because a truncated header errors out before reaching the marker and the probe
read `no stray-token message' as `the macro is alive'. **A guard that returns
`alive' when the program never ran is not a guard**; the version that worked
inserts the marker into the INTACT file, where a failure to reach it is
impossible.

Two other measurements from the same hour, both discarded rather than reported:
a batch sweep whose output was read before it had finished (its `.fail` list
was an alphabetical prefix wearing the shape of a result -- the `&` inside a
backgrounded call detached it, so the harness reported the WRAPPER as complete),
and one that spanned a peer's `busybox_diff.sh` regenerating
`include/autoconf.h` at 17:33 underneath it.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 2f920dfd4.
