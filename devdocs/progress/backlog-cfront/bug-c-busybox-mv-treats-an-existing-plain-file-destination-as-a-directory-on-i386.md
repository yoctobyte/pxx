---
slug: bug-c-busybox-mv-treats-an-existing-plain-file-destination-as-a-directory-on-i386
title: "busybox mv on i386 concatenates the source basename onto a plain-file destination; the same source is correct on x86-64"
track: C
prio: 55
type: bug
status: open
created: 2026-09-02
found-by: frankD
owner:
blocked-by:
summary: "The full-applet busybox separate build LINKS AND RUNS on i386 (266 objects, `gcc -m32`) and differs from the gcc oracle on exactly ONE of 387 cases: `mv copy.txt moved.txt` prints `mv: can't stat 'moved.txt/copy.txt': Not a directory` and exits 1, where gcc's build of the identical source exits 0. mv only builds that path when it believes the destination is a DIRECTORY, so something upstream reports a plain file, or a missing file, as one. stat/lstat/S_ISDIR/errno are NOT the cause and have been measured out: all four of gcc-x86-64, gcc -m32, pxx-x86-64 and pxx-i386 agree exactly on rc, errno and the S_IS* predicates for a plain file, a directory, a missing path, a path under a missing directory, and a path under a plain file. x86-64 is byte-identical to the oracle over all 387 cases, so this is i386-only."
---

# The case

`tools/busybox_diff.sh --separate --targets i386 --applets '<the 140-applet set>'`,
case `### mv file`, which is `mv $c/copy.txt $c/moved.txt`:

```
  oracle (gcc -m32)          pxx i386
  ### exit=0                 mv: can't stat '<d>/moved.txt/copy.txt': Not a directory
                             ### exit=1
```

and then, in the `### mv missing` case that follows, pxx emits an extra
`mv: can't rename '<d>/missing.txt': No such file or directory`. The second is
almost certainly downstream of the first -- the earlier case left the directory
in a different state -- but it has not been isolated, so it is recorded as an
observation and not as a second defect.

`<d>/moved.txt/copy.txt` is a path busybox's `mv` only constructs when it has
concluded the destination is a directory and appended the source's basename.
So the question is what told it that.

# What is already ruled out

**stat, lstat, S_ISDIR and errno.** Measured 2026-09-02, four builds of one
probe -- `gcc`, `gcc -m32`, `pxx`, `pxx --target=i386` -- byte-identical on
every row:

| probe | all four |
| --- | --- |
| `stat` of a plain file | `rc=0 isdir=0 isreg=1 mode=664 size=1` |
| `stat` of a directory | `rc=0 isdir=1 isreg=0` |
| `lstat` of a plain file | `rc=0 isdir=0 isreg=1` |
| `stat` of a missing path | `rc=-1 errno=2` (ENOENT) |
| `stat` under a missing dir | `rc=-1 errno=2` |
| `stat` under a plain FILE | `rc=-1 errno=20` (ENOTDIR) |

`sizeof(struct stat)` legitimately differs (96 on pxx x86-64, 68 on pxx i386,
against glibc's 144 and 88) and the two offsets the probe checks are the same
where it matters; the layout is not shared with glibc and does not need to be,
because nothing crosses that boundary.

**Not the C frontend refusing anything.** All 265 translation units become i386
objects, and with `libbb/bb_bswap_64.c` added (see below) all 266 link.

# Where to look next

`cp_mv_stat2` in `libbb/copy_file.c` is the function that returns 3-for-directory,
and `coreutils/mv.c` is its only caller for this decision. It branches on the
return of a `stat_func` POINTER, and on `errno != ENOENT`. Since the syscalls
and errno agree, the candidates are the layers above:

- the function-pointer call itself (`mv` passes `lstat` or `stat` by address),
- `concat_path_file` / `last_char_is`, which build the concatenated path,
- `getopt32`'s option word, if `mv` is taking a flag it was not given.

**The decisive next measurement is a minimal repro against the built binary**,
which needs `busybox_diff.sh --separate --keep` so `$WORK/p_i386` survives; the
run takes ~20 minutes and the harness deletes its work directory otherwise.

# Why this is worth a ticket rather than a note

It is the ONLY divergence in 387 cases on the second architecture, and it is a
wrong ANSWER rather than a refusal: `mv` reports failure and leaves the file
where it was. A user's `mv a b` silently not moving anything is the shape of
bug that the goal's "runs a minimal system with the compiler on it" cannot
tolerate, and it is one case away from i386 being green.
