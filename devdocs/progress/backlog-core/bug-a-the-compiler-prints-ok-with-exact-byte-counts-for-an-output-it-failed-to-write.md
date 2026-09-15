---
slug: bug-a-the-compiler-prints-ok-with-exact-byte-counts-for-an-output-it-failed-to-write
track: A
prio: 70
type: bug
blocked-by: []
status: backlog
found: 2026-09-11
found-by: frankuser
owner: unassigned
summary: "No write in elfwriter.inc checks its result and sysclose is unchecked too, so on ENOSPC the compiler short-writes the binary and still prints `ok: ... [code=NB data=NB bss=NB]` with the counts it INTENDED. Measured: a test binary came out 1163348 bytes against a good build's 1585236, 422KB short, reported ok, and segfaulted. It reddened one row of a full NilPy tier as a codecs bug."
---

# `ok:` is printed for an output the compiler failed to write

## The fact, measured

A full `make test-nilpy` on 2026-09-11 reddened exactly one row,
`test_nilpy_qualified_ctor_does_not_capture_its_args`, with **`Segmentation
fault`** and an empty diff — all six expected lines missing. The compile line
above it read:

```
ok: /tmp/pxx-testtmp-.../test_nilpy_qualctorargs26  [code=1470232B  data=114772B  bss=88940B]
```

The binary left on disk was **1,163,348 bytes**. A good build of the same source
is **1,585,236**. It was 421,888 bytes short, the compiler reported success with
three exact byte counts, and the truncated ELF died on the first instruction it
did not have.

The cause was ENOSPC: `/tmp` went to 0 free during the run. The row passes on
rerun at HEAD and under the pin, so nothing is wrong with the codecs path that
the row is named for.

## Why this is the house failure mode and not a disk problem

The disk filling is an accident. The defect is that **the compiler's success
message is a statement about its intent rather than about the file**: `code=`,
`data=` and `bss=` are the sizes it meant to write, printed unconditionally. So
the instrument does not error — it answers, correctly, about something else.

The consequence is the expensive part. A short write produces:

- a binary that segfaults with no diagnostic,
- at a test whose name points at an unrelated subsystem,
- inside a tier, where it reads as a regression in whatever landed recently.

A seat attributing that red to a range would have bisected a codecs ticket that
was never broken. This one was caught only because the same session had caused
the ENOSPC and recognised the timestamps.

## Where

`compiler/elfwriter.inc`, all three write paths, none checked:

| line | call |
| --- | --- |
| 2075-2079 | `syswrite(f,Code,CodeLen)`, `syswrite(f,Data,DataLen)`, `syswrite(f,DbgBuf,DbgLen)` |
| 2084 | `sysclose(f)` |
| 1944-1950 | the `Blockwrite` variant, including the `padN` loop |
| 2382 | the third `Blockwrite` site |
| 453-454 | `syswrite(f, TokChars, len)` then `sysclose(f)` |
| 459-465 | `writeU8`/`writeU16`/`writeU32` — `Blockwrite`, no `IOResult` |

`sysclose` matters as much as the writes: a filesystem may only report a
deferred write error at close, so checking the writes alone still lets this
through.

## The fix

Check each write's result against the length asked for, check the close, and
make a short write a hard error that **suppresses the `ok:` line**. The message
must name the path and the shortfall, because "wrote 1163348 of 1585236 bytes
to X" is self-diagnosing where a segfault twenty minutes later is not.

## Verifying it without a full filesystem — no sudo, no mount

`ulimit -f` caps a file's size in 512-byte blocks and makes the write fail with
EFBIG, which is the same short-write shape as ENOSPC:

```sh
( ulimit -f 64; ./compiler/pascal26 test/hello.pas /tmp/trunc )   # expect a LOUD failure
```

That is the positive control, and it is drawn from the right population: the
thing under test is "a write that cannot complete", not "a disk that is full".
Assert that the `ok:` line is ABSENT and the exit status nonzero — asserting the
error text alone would pass on a compiler that prints both.

## What this is not

Not the cause of the tier red it produced — that row is fine. Not a `/tmp`
capacity ticket; the inode/space hazards are already in CLAUDE.md. The defect is
the unchecked write, and it is a wrong answer on every filesystem that can fill,
every quota, and every NFS mount that drops a write at close.

## THIRD AND FOURTH OCCURRENCES, 2026-09-15 — two seats, one hour, one full /tmp

Raised 55 -> 70 on recurrence, not on a new argument. The defect is unchanged;
what is new is that it has now voided a measurement three times in four days,
and each time the seat that hit it spent real effort attributing a red before
finding the disk.

**Track N tier.** `test_nilpy_property26` printed
`ok: [code=1335064B data=88532B bss=56436B]` and then segfaulted with EMPTY
output, so the diff against a full `.expected` deleted every line — the exact
shape of a real regression in whatever landed last. It was read as one until the
size was checked. The dead binary was **1421312 bytes = 4096 x 347**, exactly a
filesystem block boundary; the correct rebuild is **1423828**, a multiple of
nothing.

**A NEW AND CHEAPER DISCRIMINATOR THAN THIS TICKET CURRENTLY RECORDS.** The
existing guidance is to compare the size against a fresh build, which costs a
build and needs a known-good tree. It is not needed: **a write killed by ENOSPC
ends on a page, a block or a power of two, and a real one does not.** One
`ls -l` answers it. The lekkerzeilen seat found the same signature independently
the same hour in a completely different artefact — a run log that stopped at
**458752 bytes = 448 KiB exactly** — and the round number was likewise the only
thing that gave it away, since every count in that experiment was a `grep -c`
over that file and would simply have reported fewer events.

**AND THE BLAST RADIUS IS THE WHOLE RUN, WHICH THIS TICKET DOES NOT SAY.** The
tier had printed `ok:` for **490 programs** before the one that died, all
compiled while the disk was on its way down. A truncated binary only fails if
the program reaches the missing part, so any of those 490 could be truncated and
green. There is no trustworthy prefix: the run is void, and keeping the 490
while re-running the tail is the trap. The stale truncated binaries must also be
cleared from the scratch directory, or they survive into the next run at the
path it writes to.

**Cheap mitigation available to any caller today, independent of this fix:**
record `df -Pm` before and after a long run INSIDE the log, and read it as part
of the verdict. It does not prevent the corruption but it makes it attributable
in one line instead of an evening. Worked, with both artefacts and the general
form: `devdocs/dev/debugging-playbook.md`, "A WRITE KILLED BY ENOSPC ENDS ON A
ROUND NUMBER".
