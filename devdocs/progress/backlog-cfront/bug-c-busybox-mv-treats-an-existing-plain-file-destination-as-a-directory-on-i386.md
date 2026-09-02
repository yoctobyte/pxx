---
slug: bug-c-busybox-mv-treats-an-existing-plain-file-destination-as-a-directory-on-i386
title: "busybox mv on i386 completes the rename and then runs one loop iteration too many -- argv pointer identity, not stat"
track: C
prio: 55
type: bug
status: open
created: 2026-09-02
found-by: frankD
owner:
blocked-by:
summary: "`mv A B` on the i386 build RENAMES A TO B SUCCESSFULLY and then prints `mv: can't stat 'B/A': Not a directory` and exits 1. The move happens; the error is an EXTRA LOOP ITERATION after it. So the suspect is not the destination check and not stat -- it is the do-loop terminator at coreutils/mv.c:188, `while (*++argv && *argv != last)`, which ends the loop by POINTER IDENTITY against `last = argv[argc - 1]` (line 82). The gcc -m32 build of the identical source ends the loop after one pass. stat/lstat/S_ISDIR/errno are measured out across four builds. Reproduces at `--applets "mv cp"` -- 34 objects, 14 cases, a few minutes -- so the 140-applet run is NOT needed to work on it. One-line repro in the body."
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

# 2026-09-02, later — the move SUCCEEDS, and that moves the suspect

Reproduced at small scope, which is the first thing worth knowing: **the
140-applet run is not needed.** `tools/busybox_diff.sh --separate --keep
--targets i386 --applets "mv cp"` is 34 objects and 14 cases and fails
identically, so the edit-build-measure loop here is minutes, not half an hour.

The one-line repro, against the kept `p_i386/mv`:

```
$ D=$(mktemp -d); printf 'x\n' > $D/copy.txt
$ tools/run_target.sh i386 ./p_i386/mv $D/copy.txt $D/moved.txt
mv: can't stat '/tmp/.../moved.txt/copy.txt': Not a directory
exit=1
$ ls $D
moved.txt
```

**`moved.txt` is there and `copy.txt` is gone. The rename WORKED.** The error is
produced afterwards, which eliminates the branch the message points at -- and
eliminates the initial `cp_mv_stat` decision too, because "not a directory" is
exactly the branch that reaches `goto DO_MOVE` and performs the rename. The
first section's four-build stat measurement was necessary but it was aimed one
layer below where the bug is.

`'moved.txt/copy.txt'` is `concat_path_file(last, basename(*argv))`, in the
do-loop body at `coreutils/mv.c:113`. Reaching it after a successful `DO_MOVE`
means the loop went round again. Its terminator, line 188:

```c
	} while (*++argv && *argv != last);
```

with `last = argv[argc - 1]` at line 82. **The loop ends by comparing a POINTER
in argv against a pointer taken out of argv.** For `mv A B` that is
`argv[1] != argv[1]` -- false, one pass -- which is what the `gcc -m32` build of
the identical source does.

So the question is why, on the i386 build, `*argv` after the `++` is not `last`.
Candidates, none measured:

- `argv` pointer identity through the i386 startup path: whether the array the
  program sees is the one `last` was taken from;
- `argc` disagreeing with the array, so `argv[argc - 1]` is not its last element;
- codegen for `*++argv` inside a `while` condition on i386 -- a pre-increment on
  a pointer-to-pointer whose result is then read again in the same expression.

**The cheap discriminator is a probe, not a build**: print `argc`, every
`argv[i]` pointer and `last` from a five-line C program built `--target=i386`,
and compare against `gcc -m32`. If the pointers already disagree there, this is
not an `mv` bug at all and the ticket re-lanes to A.

The title and summary above were rewritten on this pass. The originals said mv
"treats a plain-file destination as a directory", which is what the message
looks like and is not what happens.
