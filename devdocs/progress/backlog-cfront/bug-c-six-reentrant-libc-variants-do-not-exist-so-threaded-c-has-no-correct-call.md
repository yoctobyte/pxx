---
slug: bug-c-six-reentrant-libc-variants-do-not-exist-so-threaded-c-has-no-correct-call
track: C
prio: 40
type: bug
status: backlog
created: 2026-09-19
found-by: frankS
owner: ""
blocked-by: []
summary: "MEASURED 2026-09-19: rand_r, getpwnam_r, getpwuid_r, getgrnam_r, getgrgid_r and getservbyname_r have NO definition in lib/crtl/src and NO declaration in lib/crtl/include. That is worse than the non-reentrancy it sits beside: POSIX explicitly PERMITS rand/getpwnam/getgrnam/getservbyname to keep static state, and the standard's own remedy is the _r spelling — so where the _r exists the plain one racing is not a defect, and where it does NOT exist a threaded C program has no correct call available at all. It cannot even work around us. The ones that ARE present and fine: strtok_r, strerror_r, asctime_r, ctime_r, gmtime_r, localtime_r. Found while censusing what else in crtl is one process-global after errno went __thread (that fix: done/bug-a-errno-is-one-global-across-all-threads-so-a-thread-reads-another-threads-failure). DO NOT RANK THIS ON THE 46 file-scope statics the census counted — most of those are the POSIX allowance and are not defects; the number that matters is six."
---

# Six reentrant variants are absent, not merely unused

## What was measured

A census of file-scope `static` non-const objects in `lib/crtl/src/*.c`: **46
objects across 15 of 32 modules**. A first pass reported 163 in `stdio.c` alone
— that regex was matching prototypes and `extern` declarations, so it is not
the number here and is recorded only so nobody reproduces it and believes it.

**The count is not the finding, and a census of statics is the wrong
instrument for the question.** POSIX explicitly permits `strtok`, `asctime`,
`ctime`, `rand`, `strerror`, the `getpw*`/`getgr*`/`getserv*` families and
`getopt` to keep static state. A static there is the standard working as
designed. The real question is whether the escape hatch exists:

    present  (def in lib/crtl/src AND decl in lib/crtl/include):
      strtok_r  strerror_r  asctime_r  ctime_r  gmtime_r  localtime_r

    ABSENT   (no definition anywhere in lib/crtl/src, no declaration
              anywhere in lib/crtl/include):
      rand_r  getpwnam_r  getpwuid_r  getgrnam_r  getgrgid_r  getservbyname_r

## Why the absent six are a different class

Where the `_r` exists, the plain call racing is **not our defect** — it is the
documented contract, and a threaded program that wants safety has somewhere to
go. Where it does not exist, a threaded C program has **no correct call in our
libc**: the plain spelling races and the reentrant spelling will not link.
There is no workaround available to the program's author.

## Fix shape

Each is a small function over state the plain version already computes; the
plain one becomes a wrapper over the `_r` writing into its existing static,
which is how they are normally related and avoids a second copy of the parsing.
`rand_r` is the smallest (`__crtl_rand_state` is one `unsigned long long` in
`stdlib.c`) and is a reasonable first one.

## Positive control for any fix

A row that links and calls each `_r`, and — because "it links" is also what a
declaration with no definition can look like until the linker runs — asserts
the RESULT differs from a second call with a different buffer. An expected
value that collides with a default would not separate a working `_r` from a
stub returning zero.

## Scope note

This is about ABSENCE, not about the races. The still-open per-thread-state
work is [[bug-a-a-foreign-thread-shares-the-main-thread-s-heap-magazine]].
