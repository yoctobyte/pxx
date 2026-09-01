---
slug: feature-c-crtl-gaps-for-a-79-applet-busybox-userland
title: "The fifteen crtl gaps a 79-applet busybox userland hits, enumerated and closed"
track: C
prio: 55
type: feature
status: done
created: 2026-09-02
found-by: frankD
owner: frankD
blocked-by: []
summary: "ALL FIFTEEN CLOSED 2026-09-02, and the userland they were blocking is GREEN: 79 applets, 148 translation units, 148 objects, one real link, 256 cases byte-identical to the gcc oracle on x86-64. The list was measured rather than guessed. Added: /etc/group lookups (getgrent/getgrnam/getgrgid/getgrouplist), /etc/mtab reading (setmntent/getmntent/endmntent/hasmntopt), getline/getdelim, fseeko/ftello, getgroups, setsid, clock_settime, getlogin_r/getlogin, mktemp, popen/pclose. Two were not missing functions at all: RAND_MAX was C99's MINIMUM of 32767 and awk #errors on anything below 0x7fffffff (the macro AND the generator were widened together), and system() was a -1 stub whose "no command processor" note had stopped being true.
---

# The list, from attempting the target

The 26-applet userland is GREEN by separate compilation. Widening the set to 79
applets gives 148 translation units, of which **133 compile**. What stops the
other fifteen, verbatim:

```
coreutils/date.c            clock_settime
coreutils/df.c              setmntent
coreutils/factor.c          (compiler HANG -- fixed, see below)
coreutils/id.c              getgrouplist
coreutils/logname.c         getlogin_r
coreutils/mktemp.c          mktemp
coreutils/stat.c            getgrgid
coreutils/tsort.c           getline
editors/awk.c               #error "Not implemented for this value of RAND_MAX"
libbb/bb_getgroups.c        getgroups
libbb/bb_pwd.c              getgrnam
libbb/dump.c                fseeko
libbb/find_mount_point.c    setmntent
libbb/vfork_daemon_rexec.c  setsid
util-linux/hexdump_xxd.c    fseeko
```

`coreutils/factor.c` is closed:
[[bug-c-a-macro-call-with-more-than-16-arguments-is-silently-mis-expanded]].

## Groups, because they are not fourteen separate jobs

- **group database** — `getgrnam`, `getgrgid`, `getgrouplist`, `getgroups`.
  `grp.h` exists and is thin. This is one piece of work, and `pwd.h`'s existing
  passwd reader is the shape to follow.
- **stdio** — `getline`, `fseeko`/`ftello`. `getline` is the one with real
  reach: it is how most POSIX code reads a line of unknown length.
- **process/session** — `setsid`, `getlogin_r`.
- **mounts** — `setmntent`/`getmntent`/`endmntent`. `mntent.h` already exists,
  which is the trap: the header is there and the functions are not.
- **time** — `clock_settime`. Needs a PAL entry; `PalSync`'s chain is the
  pattern.
- **`mktemp`** — the deprecated one, separate from the existing `mkstemp`.
- **`RAND_MAX`** is NOT a missing function and should not be worked as one.
  `editors/awk.c` selects an implementation by testing `RAND_MAX` against a
  small set of known values and `#error`s otherwise. Read what crtl's `rand()`
  actually is before changing the macro: the value and the generator have to
  agree, and matching the macro alone would be the name standing in for the
  thing.

## Not in scope

`utimensat`/`futimens` for `touch` is its own ticket
([[feature-c-crtl-utimensat-and-futimens]]). No applet beyond these 79 has been
attempted, so this list is what 79 hits and not what busybox needs.


## ALL CLOSED 2026-09-02

```
busybox-diff: applets=... (79)   translation units=148
  ORACLE  gcc separate build, 148 objects (256 cases)
  ORACLE  busybox agrees with the gcc build
  note    x86_64   148 objects linked separately (53294928 bytes)
  PASS    x86_64   byte-identical to the gcc oracle over 256 cases
busybox-diff: GREEN
```

Every function was diffed against a **gcc build of the same source**, not
reasoned about. `test/c_crtl_busybox_surface.c` carries the rows that had a
wrong answer available, and says which wrong answer each one is aimed at.

**Two of the fifteen were not missing functions**, and calling them that would
have produced the wrong fix:

- **`RAND_MAX`** was 32767 — C99's required *minimum*, entirely legal, and
  `editors/awk.c` `#error`s on anything below `0x7fffffff`. The header alone was
  not the fix: raising the macro over a 15-bit generator leaves every high bit
  permanently zero, which passes an in-range test. The state widened to 64 bits
  and the result now comes from the high half, and the test asserts a high bit
  is actually seen.
- **`system()`** was a `-1` stub carrying the note *"the libc-free runtime has
  no command processor"*. True when written; crtl has had fork, execvp, pipe,
  dup2 and waitpid for a while. It runs `/bin/sh -c` now, and `system(NULL)`
  answers by LOOKING for `/bin/sh` rather than by returning a constant.

The rest were ordinary: `grp.c` and `mntent.c` are new files following `pwd.c`'s
shape (**no NSS**, and a too-long line skipped rather than truncated, for the
same reason); `setsid`, `getgroups` and `clock_settime` are full PAL chains with
syscall numbers **read off this box's headers** (`asm/unistd_64.h`,
`asm/unistd_32.h`, `asm-generic/unistd.h`) — except arm32's `clock_settime`,
derived from the −1 relation this file's own `clock_gettime` numbers already
show, and said so in the comment.

## What is still not here

`utimensat`/`futimens` for `touch`
([[feature-c-crtl-utimensat-and-futimens]]) — that is why the applet set is 79
and not 80. `addmntent` is deliberately absent: nothing in the corpus writes
mtab, and a half-written entry is worse than a missing call.
