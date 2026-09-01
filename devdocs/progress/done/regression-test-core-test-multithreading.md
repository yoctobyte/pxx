---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The failing step (line 2 of 2) named no source of its own, but this job has only ONE source — so first-source and only-source are the same file here and there is no other lane in frame. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 10 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_multithreading.pas@1 at 039be8b4aa97 in step 2/2, `/tmp/test_multithreading26 | grep -q "multithreading test completed successfully"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-01T20:46:57Z
- **Test source:** test/test_multithreading.pas
- **Failing step:** line 2 of 2 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  /tmp/test_multithreading26 | grep -q "multithreading test completed successfully"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_multithreading.pas@1'` at 039be8b4aa97ff662460ce2a0d65b314e0b7c134

## Range
> **The named sha `039be8b4aa97` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `039be8b4aa97`, last good `12c916c5c9ca`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-2539273/test_multithreading26  [code=69288B  data=3988B  bss=43556B  procs=138]
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-01 — auto-closed by the seven watcher: `test-core#src:test/test_multithreading.pas@1` passes at fe54f86f7dee (tier native); it was red at 039be8b4aa97. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
