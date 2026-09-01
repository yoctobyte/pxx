---
slug: feature-c-crtl-gaps-for-a-79-applet-busybox-userland
title: "The fourteen crtl gaps a 79-applet busybox userland hits, enumerated"
track: C
prio: 55
type: feature
status: backlog
created: 2026-09-02
found-by: frankD
owner: ""
blocked-by: []
summary: "Measured, not guessed: with the 26-applet userland GREEN, a 79-applet attempt compiles 133 of 148 translation units. One failure was a compiler hang (fixed, bug-c-a-macro-call-with-more-than-16-arguments-is-silently-mis-expanded); the other fourteen are crtl gaps, and this ticket lists exactly which function each file wants. Thirteen are missing declarations/implementations (getline, fseeko, setsid, mktemp, getgroups, getgrnam, getgrgid, getgrouplist, getlogin_r, setmntent, clock_settime); the fourteenth is different in kind -- editors/awk.c #errors on crtl's RAND_MAX value."
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
