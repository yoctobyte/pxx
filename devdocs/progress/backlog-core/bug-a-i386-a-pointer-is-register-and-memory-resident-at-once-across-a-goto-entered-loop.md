---
slug: bug-a-i386-a-pointer-is-register-and-memory-resident-at-once-across-a-goto-entered-loop
title: "i386: a pointer variable is register- and memory-resident at once across a goto-entered loop, so ++ updates one and the loop test reads the other"
track: A
prio: 55
type: bug
status: open
created: 2026-09-02
found-by: frankD
owner:
blocked-by:
summary: "INSTRUMENTED AND LOCALISED. On i386, `mv A NEW` moves the file and then takes one extra loop pass. The instrumented trace shows `argv` holding the SAME address at both evaluations of `while (*++argv && *argv != last)` while the loop still terminates after two -- which is only consistent with `argv` being register- and memory-resident at once: the `++` advances a REGISTER (pass 1 to the `NEW` slot, pass 2 to the NULL terminator, which short-circuits and ends the loop), while the `!= last` comparison and the body both re-read the MEMORY slot the `++` never wrote back, so the test asks `"A" != "NEW"` and grants the extra pass. That is also why the message reads `NEW/A` and not `NEW/NEW`. argc, optind, flags and last are all correct, so getopt32 and its varargs are exonerated along with stat/lstat/S_ISDIR/errno and argv pointer identity. Five minimal programs failed to reproduce it standalone; busybox itself is the reproducer, seconds per iteration via the single-TU rig in the body. RE-LANED TO A: i386 code generation, not the C frontend."
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

# 2026-09-02, night — the argv hypothesis is REFUTED, and the boundary is sharp

Everything in the section above about `coreutils/mv.c:188` and pointer identity
is **wrong**, and it is left standing only because the measurement that killed
it is the useful part. Each row below is a separate probe, all four builds
(`gcc`, `gcc -m32`, `pxx`, `pxx --target=i386`) unless stated.

| probe | result |
| --- | --- |
| `argc`, every `argv[i]` slot and value, and `last = argv[argc-1]` | **identical** on all four |
| the terminator `do {} while (*++argv && *argv != last)`, 1 and 2 passes | **identical** on all four |
| a `goto` from outside INTO a `do-while` body, skipping the statements above the label | **identical** on all four |
| the same, with eight extra live locals for register pressure, at `-O0` and `-O2` | **identical** on all four |

So the loop shape, the jump into it, and the argv it walks are all exonerated at
C level on i386. The bug is not where the first two versions of this ticket said.

## What the applet actually does — the sharp boundary

Against the built `p_i386/mv`, one temp dir per row:

| command | result |
| --- | --- |
| `mv A NEW` (dest does not exist) | **moves, then** `can't stat 'NEW/A'` |
| `mv A EXIST` (dest is a plain file) | **moves, then** `can't stat 'EXIST/A'` |
| `mv -T A NEW` | **moves, then** `can't stat 'NEW/A'` |
| `mv A DIR` (dest is a directory) | **correct, silent** |
| `mv -t DIR A` | **correct, silent** |

**Every failing row is one that reaches `goto DO_MOVE`; every correct row enters
the loop normally.** `-T` failing with it matters: that is the second, separate
`goto DO_MOVE` at line ~102, so this is about the jump, not about one branch.

**And `'NEW/A'` is the sharpest fact in the ticket.** The concatenation is
`concat_path_file(last, bb_get_last_path_component_strip(*argv))`. On a genuine
second pass `*argv` would be `NEW` and the string would be `NEW/NEW`. It is
`NEW/A`, so **on the extra pass `*argv` is still the FIRST argument** -- the
increment in `*++argv` did not take effect for that pass, and then did on the
next one, which is why it terminates instead of spinning.

Not optimiser-dependent: `-O1` and `-O2` reproduce identically.

## The measurement rig, which is the reusable part

Two things make this cheap now, and both were expensive to find:

1. **It reproduces at `--applets "mv cp"`** -- 34 objects, 14 cases, a few
   minutes. The 140-applet run is not needed.
2. **One TU can be swapped without rebuilding anything else.** With
   `--separate --keep`, recompile the single wrapper and relink:

   ```
   cd $WORK
   ( cd $BB && pascal26 --emit-obj -O2 --target=i386 -I. -Iinclude -Ilibbb \
       $WORK/wrap/coreutils_mv.c $WORK/obj/coreutils_mv.o )
   gcc -m32 -o /tmp/t/busybox obj/*.o && ln -sf busybox /tmp/t/mv
   tools/run_target.sh i386 /tmp/t/mv A NEW
   ```

   busybox dispatches on `argv[0]`, so the symlink is required -- invoking the
   binary by any other name answers `applet not found`, which reads like a build
   failure and is not one.

**`-O0` is NOT available for this bisection**, and the reason is busybox's, not
ours: `obj/coreutils_mv.o:(.data+0x600): undefined reference to
`BUG_xatou32_unimplemented'`. That symbol is a deliberate link-time assertion
which only disappears when the compiler folds a provably-dead branch, so an
unoptimised busybox TU cannot link. Do not read it as an i386 regression.

## Next measurement

Instrument `mv_main` itself -- print `argc` and `optind` immediately after
`argv += optind`, then `last`, `*argv` and `argv` at the top of the body and
again at the `while` -- using the single-TU swap above. That distinguishes the
two survivors: `argv` being re-read from a stale location after the inbound
jump, versus the `++` being applied to a copy. Both are backend concerns, so
**this most likely re-lanes to A**; it has not been re-laned yet because no
measurement has yet put the fault below the C level, and the four probes above
each failed to.

# 2026-09-02, night — INSTRUMENTED. `argv` is register- and memory-resident at once

`mv_main` instrumented through the single-TU rig (an edited COPY of mv.c, the
busybox tree untouched; note `-Icoreutils` is needed or `libcoreutils/coreutils.h`
does not resolve). `mv A NEW`, i386, `-O2`:

```
DBG post-getopt argc=2 optind=1 flags=0 argv=0xfff0f8d8 argv[0]=A argv[1]=NEW
DBG last=0xfff1150d (NEW) &argv[argc-1]=0xfff0f8dc
DBG body     argv=0xfff0f8d8 *argv=A dest=NEW last=0xfff1150d(NEW) eq=0
DBG prewhile argv=0xfff0f8d8 *argv=A last=0xfff1150d
mv: can't stat 'NEW/A': Not a directory
DBG prewhile argv=0xfff0f8d8 *argv=A last=0xfff1150d
```

`argc`, `optind`, `flags` and `last` are all **correct** -- `flags=0` in
particular, so the earlier suspicion of a stray `OPT_DESTDIR` from getopt32's
varargs is dead too.

**`argv` holds 0xfff0f8d8 at both `prewhile` prints, and the loop still
terminates after two passes.** Those two facts cannot both be true of a single
`argv`, and that is the finding:

- the `++` in `*++argv` advances a REGISTER copy: pass 1 lands on the `NEW`
  slot (non-NULL, so `&&` continues), pass 2 lands on the NULL terminator,
  which short-circuits and is what finally ends the loop;
- every other read -- the `!= last` comparison, `*argv` in the body, and the
  instrumentation itself -- reads the MEMORY slot, which the `++` never wrote
  back. So the comparison asks `"A" != "NEW"`, answers true, and grants the
  extra pass.

That also explains the concatenation being `NEW/A` rather than `NEW/NEW`, which
was the first clue, and why the loop stops instead of spinning.

**The absent `DBG body` line on pass 2 corroborates rather than contradicts**:
`cp_mv_stat` on the concatenated path fails, and `if (dest_exists < 0) goto RET_1;`
sits ABOVE the `DO_MOVE:` label, so pass 2 legitimately skips it.

**One honest caveat.** The instrumentation reads `argv` the same way the body
does, so "argv never changed" is a statement about what the PROGRAM observes,
not an independent view of the register. That is the defect rather than a
limitation of the probe -- the program's own reads are the thing that is wrong --
but a disassembly of `mv_main` around the loop is what would show the two
locations directly, and it has not been done.

## Why it does not reproduce standalone

Five minimal programs failed to trigger it, each closer than the last: the
terminator alone; a `goto` from outside into a `do-while` body; the same with
eight extra live locals at `-O0` and `-O2`; the same with the parameter
reassigned by a NON-CONSTANT (`argv += opt_index`, the `argv += optind` shape);
all correct on all four builds. Whatever forces `argv` to be both
register-allocated and memory-resident needs more of `mv_main` than these have --
most likely the spill pressure of the real body, which contains `bb_perror_msg`,
`copy_file`, `remove_file` and a nested error ladder.

**So the reproducer of record is busybox itself**, via the rig above, which is
seconds per iteration. Do not spend more time shrinking it before looking at the
generated code; the trace already localises it.

## Re-laned to A

This is i386 backend code generation, not the C frontend: the frontend's own
loop and jump lowering is correct in isolation on this target at both `-O0` and
`-O2`, and the divergence is between two storage locations for one variable.
Track C found it and has taken it as far as source-level measurement can.
