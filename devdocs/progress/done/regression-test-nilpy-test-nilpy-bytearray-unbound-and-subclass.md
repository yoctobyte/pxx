---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 1 of 24, `./compiler/pascal26 test/test_nilpy_bytearray_unbound_and_subclass.npy /tmp/test_nilpy_baunbound26`, which names `test/test_nilpy_bytearray_unbound_and_subclass.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_bytearray_unbound_and_subclass.npy at b4104386ae9c in step 1/24, `./compiler/pascal26 test/test_nilpy_bytearray_unbound_and_subclass.npy /tmp/test_nilpy_baunbound26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-19T15:16:10Z
- **Test source:** test/test_nilpy_bytearray_unbound_and_subclass.npy test/test_nilpy_bytearray_unbound_and_subclass.expected
- **Failing step:** line 1 of 24 of the job's recipe; it names `test/test_nilpy_bytearray_unbound_and_subclass.npy`.
  ```
  ./compiler/pascal26 test/test_nilpy_bytearray_unbound_and_subclass.npy /tmp/test_nilpy_baunbound26
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_bytearray_unbound_and_subclass.npy'` at b4104386ae9c393702223f151f8e29b902868140

## Range
> **The named sha `b4104386ae9c` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b4104386ae9c`, last good `11e0c581c80d`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:68: error: Nil Python: add overrides TPyList.add with a different result type, in a class laid out after its base was compiled (it has several bases, or derives from one that does) -- annotate both results with the same type
(tail)
pascal26:68: error: Nil Python: add overrides TPyList.add with a different result type, in a class laid out after its base was compiled (it has several bases, or derives from one that does) -- annotate both results with the same type
  near: ( list ) :   >>> def add ( 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-19 — auto-closed by the borg watcher: `test-nilpy#src:test/test_nilpy_bytearray_unbound_and_subclass.npy` passes at ff2d50a2bde9 (tier full); it was red at b4104386ae9c. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
