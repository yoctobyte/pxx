---
slug: bug-c-six-reentrant-libc-variants-do-not-exist-so-threaded-c-has-no-correct-call
track: C
prio: 40
type: bug
status: done
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

## RESOLVED 2026-09-19 (frankS) — all six implemented

`rand_r` (stdlib.c), `getpwnam_r`/`getpwuid_r` (pwd.c), `getgrnam_r`/`getgrgid_r`
(grp.c), `getservbyname_r` (netdb.c), each declared in its own header.

### The fix shape this ticket prescribed was WRONG, and backing it out is the finding

The "Fix shape" section above says *"the plain one becomes a wrapper over the
`_r`"*. I wrote it that way first. **It is a regression and it does not show up
on a normal file**, which is why it is recorded here rather than quietly
changed — this is an assertion-written-from-a-prediction, and the prediction
was mine.

The two forms must answer an over-long line **differently**:

| | over-long line |
| --- | --- |
| plain | **SKIP it and keep looking** — each file's header says so, and argues it: a skipped line at worst answers "no such user", a truncated one invents a user whose home directory is a prefix of the real one |
| `_r` | **ERANGE** — POSIX requires it, and the caller chose the buffer, so silently skipping the entry they asked for would be a wrong ANSWER rather than a failure |

Routed through the `_r`, **one** over-long line anywhere in `/etc/passwd` turns
`getpwnam()` into "no such user" for every entry after it.

`grp.c` and `netdb.c` have a second, independent reason: the plain forms get
dedicated `GR_MEM_MAX`/`SERV_ALIAS_MAX` (256) pointer arrays, while the `_r`
forms carve the member/alias array out of the caller's buffer. Wrapping would
shrink a long group's member list to however many pointers fit after the line —
`wheel:x:10:alice,bob` reported without bob, on a file that works today.

**What IS shared is the parser**, which is where duplication would actually
hurt: `pw_parse`/`gr_parse`/`serv_parse` now take their output struct (and, for
the two with lists, the array and its capacity), so there is one copy of "what
the fields mean". The residual overlap is a four-line match loop, and the two
loops differ in exactly the way the table above says they must.

`rand_r` cannot share `rand()`'s generator either, and that is **forced by the
signature**: POSIX types the seed `unsigned int`, so 32 bits of state where
`rand()` keeps 64 — and `rand()`'s whole design is to return the HIGH half,
because a power-of-two LCG's low bits have short periods. With 32 bits there is
no high half. It uses the classical three-round construction; the range still
matches `RAND_MAX`, and the two sequences differ, which is conforming.

### Test

`test/c_crtl_reentrant_lookups.c`, wired into `lib-test` beside `cpwd`.

Rows are **relations** — each `_r` answer against the plain one on the same
input — so no per-machine constant is baked in (root's shell and ssh's port
differ per box). Agreement alone is not enough, though: a "reentrant" function
that called the plain one and returned its static pointer would pass every
agreement row, which is the exact bug class this closes. So the load-bearing
assertion is by **address**: the returned strings must live inside the CALLER'S
buffer and the plain form's must not. A stub cannot fake that. Plus a
two-buffer row proving both results stay valid simultaneously, an ERANGE row,
and for `rand_r` a not-a-constant row (a stub returning 0 satisfies every range
and determinism check).

### Oracle-checked, with one deliberate divergence

Built with gcc against glibc: **every row passes except one**, and that row is
a real contract fork, measured — glibc returns `ENOENT` for a not-found entry
where POSIX says *"0 shall be returned and result shall be set to a null
pointer"*. Linux's own `getpwnam_r(3)` records that implementations deviate.

We follow POSIX, and it is also the **safer** direction rather than merely the
purer one: both set `*result` to NULL, so the portable idiom works under
either, while code treating any nonzero rc as a hard error gets one from glibc
on an ordinary missing user and not from us. The fixture names that row so the
gcc failure explains itself, and says not to "fix" it by matching glibc.

### Not inert until the next pin

`lib/crtl` sources are compiled live, not carried in the pin, so this works
under `$(PXX_STABLE)` today — verified by building the fixture with
`stable_linux_amd64/default/pinned`: `fails=0`. The three existing fixtures
that touch these families (`cpwd`, `c_crtl_netdb_and_exec`,
`c_crtl_busybox_surface`) are still byte-identical to gcc after the parser
refactor.

## Log
- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
