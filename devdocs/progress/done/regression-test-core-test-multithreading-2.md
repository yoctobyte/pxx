---
prio: 70
track: A
status: done
---

> **Track guessed as P** from the test source. The failing step (line 2 of 2) named no source of its own, but this job has only ONE source — so first-source and only-source are the same file here and there is no other lane in frame. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_multithreading.pas@1 at 9c76d9ba089c in step 2/2, `/tmp/test_multithreading26 | grep -q "multithreading test completed successfully"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-01T21:21:57Z
- **Test source:** test/test_multithreading.pas
- **Failing step:** line 2 of 2 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  /tmp/test_multithreading26 | grep -q "multithreading test completed successfully"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_multithreading.pas@1'` at 9c76d9ba089c7f4b51bcc50cba7478db01c02c6a

## Range
> **The named sha `9c76d9ba089c` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `9c76d9ba089c`, last good `df1a8c17ce9a`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-2714290/test_multithreading26  [code=69288B  data=3988B  bss=43556B  procs=138]
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Fixed at HEAD — 2026-09-01, frankZ. Re-laned from P; it was never Track P's.

**The bisect range is empty of buildable commits and the ticket is right to say
so.** `df1a8c17ce9a..9c76d9ba089c` is three commits: two `rules:` edits to
CLAUDE.md and one tstate publish. Nothing there can change a binary — this is
not a regression, it is a pre-existing race that flipped.

Proof it predates the window, which is stronger than the window being empty:
the **PINNED v399** compiler builds this program to a **byte-identical**
binary (`sha256 53dbf4eca6fd4b55a2f2...`, same as HEAD's) and it crashes at the
same rate. Same bytes, same failure, a compiler from 2026-08-19.

## What it is

`test_multithreading.pas` makes its four workers with libc `pthread_create`. A
foreign thread never runs the `__pxxclone` stub that carves and installs a
per-thread TLS block, so it inherits its creator's `gs`. Measured with gdb:
`gs_base = 0x411f98` on all five threads, and `0x411f98` is `BSS_TLS_MAIN`.

The heap magazine lives in that block and guarded itself with a plain
load-test-store, on the premise that the only possible second entrant was a
signal handler on the same thread. Five threads in one magazine tore the
head/count pair, and the fault landed inside `PXXAlloc`'s **global** bin pop
(`FreeBins[bin] := PWord(cur)^`) reading a head of `0x8` — a magazine COUNT
where a pointer belongs. Nowhere near the magazine, which is why it read as a
heap bug.

The A/B that named it, before any theory: 18 SIGSEGV in 100 runs with the
magazine, **0 in 100** with `-dPXX_NO_HEAP_MAG`, different binaries, same box.

## The fix

`ba2682d2f` — the guard's take becomes `xchg r64, m64`, which asserts LOCK
implicitly. A shared magazine is now correct; a loser takes the global locked
path it could already take. Interleaved A/B afterwards, same box, same minute:
plain guard 8/60 SIGSEGV, xchg guard **0/60**, and 0/210 cumulative.

Guard: `test/test_heap_magazine_foreign_thread.pas`, in `test-quick`, 0.105s.
It uses `pthread_create` deliberately — a pxx-created thread cannot reproduce
this, so a guard built on `BeginThread` would have passed against the broken
compiler. Positive control measured, not assumed: reverted both compiler files,
rebuilt to `76c8be9064e0`, 20 of 20 runs SIGSEGV; restored and rebuilt to
`b9fd008f89ef`, 0 of 20.

What is NOT fixed is that the TLS block is not per-thread for a foreign thread
at all — that reaches every `gs:` slot, not just the magazine, and it is a
design question: [[bug-a-a-foreign-thread-shares-the-main-thread-s-heap-magazine]].
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 2112c18c5.
