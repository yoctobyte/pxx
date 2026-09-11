---
slug: bug-a-the-compiler-prints-ok-with-exact-byte-counts-for-an-output-it-failed-to-write
track: A
prio: 55
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
