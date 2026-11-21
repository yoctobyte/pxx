---
slug: bug-c-toybox-test-suite-failures
track: C
prio: 50
type: bug
status: open
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, toybox]
blocked-by: []
summary: "toybox's own suite: gcc build PASS 1604 / FAIL 0 / SKIP 24. A partial (contaminated) pxx run showed ~44 FAIL: cpio x12, id x4, file x4, utf8 cases in fold/fmt/echo/file (crtl has no C.UTF-8 -- expected), mkpasswd, httpd, gunzip perms, grep speed, find, cut -C; devmem likely fixed since. Needs a clean rerun and triage."
---

# toybox test failures under pxx

Run `VERBOSE=all scripts/test.sh` with the pxx binary named `toybox`.

## 2026-11-21 (claude-pxx): one cause found, the `\e` rows

The latest full pxx run on file (`~/toybox-wip/build/new.testlog`, the
2026-11-15 build) passes 1502 to gcc's 1604. Among its failures are
`echo -e \e`, `echo -e 'a\x123כּbc'`, `printf escapes`, `printf %b
escapes`, `printf %b \e` and `printf \e`.

At least the `\e` ones are pxx's C lexer, not crtl: GNU's `\e`/`\E` (ESC, 27)
was read as the letter, so `'\e'` was 101 and `"\e"` was "e". toybox's
escape table is written with `\e`. Fixed in both clexer.inc decoders (char
constants and strings), test `test/c_gnu_escape_e.c` against gcc's output.

Not re-measured: a toybox rebuilt with the fixed compiler (the replay was not
rerun). The rows above are expected to move; whether all six do is for the
next suite run to say.

## 2026-11-21 (claude-pxx): toybox rebuilt with the `\e` fix, and the sed cause

Rebuilt in scratch with pxx at 3b330fe9f9 (205 units, linked by `pxx --link`):
the suite went from **1502 to 1509** passes. The five `\e` rows (`echo -e \e`,
`printf \e`, `printf %b \e`, `printf escapes`, `printf %b escapes`) pass.
`ls -ou` and `ls -otu` pass too, but those read access times, so they are not
counted as fixed. `echo -e 'a\x123כּbc'` still fails (\u wants a UTF-8
locale).

Failures left, grouped by command: sed 22, touch 15, timeout 14, cpio 12,
stat 8, id 4, tar, readelf and fold 2 each, then single rows.

**sed (most of its 22): crtl regexec ignored pmatch[0] under REG_STARTEND when
nmatch was 0**, and answered NOMATCH. toybox's `regexec0` calls it exactly that
way for every address match (`/two/p`, `1,/two/p`, ...), while `s///` passes
nmatch 10 and worked. glibc reads pmatch[0] whatever nmatch is (nmatch counts
slots to WRITE). Fixed in lib/crtl/src/regex.c; test/c_crtl_regex.c gained
three nmatch-0 checks (matches in span, misses out of span, does not write
pmatch).

## 2026-11-21 (claude-pxx): touch -t, and what stops timeout

**touch (15 rows), two crtl causes:**
- **mktime read the fields as UTC.** It was written before localtime read the
  zone and was never revisited, so on a CET box `touch -t 01231234` stamped
  13:34. It now inverts localtime in the TZ zone and honours tm_isdst as glibc
  does. timegm keeps the UTC arithmetic, and strftime `%s` is mktime (it was
  timegm, on the same stale premise).
- **strptime had no `%C`,** so every `touch -t CCYYMMDDhhmm` was "bad date".
  It now uses glibc's rules (`%C` alone is C*100; `%C` with `%y` in either order
  is C*100+y; `%y` alone pivots at 69).

Test: test/c_crtl_mktime_local_and_strptime_century.c, in test-core, run per
zone against gcc in six zones (identical in all six and with TZ unset). The
strftime row `cstrfz` now runs gcc and pxx in the same environment instead of
pinning only gcc to UTC.

**timeout (14 rows) is not fixed here.** Its SIGCHLD handler is installed with
SA_SIGINFO, which crtl refuses on purpose. Filed as
feature-a-crtl-sigaction-cannot-honour-sa-siginfo-because-the-thread-block-has-no-slot-for-it:
the fix is a thread-block layout decision.

## 2026-11-21 (claude-pxx): measured after the regex and time fixes: 1555

Rebuilt from master 42bc80ca4b: **1555 pass** (1509 before, gcc 1604), 45
rows fixed and none newly failing. sed and stat have no failures left; touch
is down from 15 to 4. Left, grouped by command: timeout 14 (SA_SIGINFO, filed),
cpio 12, touch 4, id 4, readelf 2, fold 2, then single rows (wc, sort, seq,
paste, mkpasswd, grep speed).

**touch -d (3 of the 4): strptime had no %T** (`%Y-%m-%dT%T` is how touch
parses `2009-02-13T23:31:30Z`). Added %T, %R, %D and %F, the composites glibc
accepts, with rows in the zone test. The fourth, `touch -r`, copies the stamp
of the file the failed `-d nanoseconds` row should have set.

**Found and NOT fixed: POSIX TZ strings.** crtl's zone code reads TZif files
only. `TZ=UTC0` happens to work, but `UTC-05:00:00`, `EST5EDT` and
`CET-1CEST,M3.5.0,M10.5.0/3` all read as UTC (probe against glibc). toybox
`touch -d ...+05:00` builds exactly the first of those. No suite row failing
today depends on it. A fixed-offset parse would be easy; the DST rules (`M`
dates) are the real work, and half of it would be a plausible wrong answer.
