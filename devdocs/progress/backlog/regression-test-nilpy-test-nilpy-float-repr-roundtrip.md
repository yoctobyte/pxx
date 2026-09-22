---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 1 of 4, `./compiler/pascal26 test/test_nilpy_float_repr_roundtrip.npy /tmp/test_nilpy_float_repr26`, which names `test/test_nilpy_float_repr_roundtrip.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_float_repr_roundtrip.npy at 3daf4bc16cc1 in step 1/4, `./compiler/pascal26 test/test_nilpy_float_repr_roundtrip.npy /tmp/test_nilpy_float_repr26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-22T10:58:52Z
- **Test source:** test/test_nilpy_float_repr_roundtrip.npy tools/expect_same.sh
- **Failing step:** line 1 of 4 of the job's recipe; it names `test/test_nilpy_float_repr_roundtrip.npy`.
  ```
  ./compiler/pascal26 test/test_nilpy_float_repr_roundtrip.npy /tmp/test_nilpy_float_repr26
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_float_repr_roundtrip.npy'` at 3daf4bc16cc15bc3a670f4115ef40ad6cbb27c25

## Range
> **The named sha `3daf4bc16cc1` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `3daf4bc16cc1`, last good `5fccc890af91`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26: error: a write to the output file stored fewer bytes than asked: /tmp/testmgr-scratch-1141223/test_nilpy_float_repr26
(tail)
pascal26: error: a write to the output file stored fewer bytes than asked: /tmp/testmgr-scratch-1141223/test_nilpy_float_repr26
  check all four -- the first is the commonest and the last is the one that fools people:
    df -h <dir>   free BYTES
    df -i <dir>   free INODES -- can hit 100% while df -h reads 9%
    ulimit -f     a file-size limit truncates at a plausible size
    another pascal26 writing THIS SAME PATH -- two writers interleave,
      and the file can then end up the RIGHT size, so its size proves nothing.

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
