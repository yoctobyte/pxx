---
slug: feature-c-crtl-posix-regex-regcomp-regexec
title: "crtl has no <regex.h>, and it is the single biggest thing between busybox and a self-contained i386 build"
track: C
prio: 60
type: feature
status: open
created: 2026-09-02
found-by: frankD
owner:
blocked-by:
summary: "7 of busybox's 396 translation units stop at `C include file not found: \"regex.h\"` when built for i386 -- awk, sed, grep, expr, test, mdev and libbb/xregcomp -- and that is the largest single cause left after fifteen headers landed on 2026-09-02. Unlike those, this is not a transcription job: it needs regcomp/regexec/regerror/regfree, both BRE and ERE, and the POSIX leftmost-longest rule. On x86-64 the gap is invisible because pxx falls back to the host's /usr/include; a cross target has no fallback, which is why i386 is the instrument that found it."
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
