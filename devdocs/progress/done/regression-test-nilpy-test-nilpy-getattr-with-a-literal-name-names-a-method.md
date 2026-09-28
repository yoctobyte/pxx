---
prio: 70
track: N
status: done
---

> **Track guessed as N from the FAILING STEP** — line 1 of 27, `./compiler/pascal26 test/test_nilpy_getattr_with_a_literal_name_names_a_method.npy /tmp/test_nilpy_getattrlit26`, which names `test/test_nilpy_getattr_with_a_literal_name_names_a_method.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_getattr_with_a_literal_name_names_a_method.npy at 844ccea7a0f2 in step 1/27, `./compiler/pascal26 test/test_nilpy_getattr_with_a_literal_name_names_a_method.npy /tmp/test_nilpy_getattrlit26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-28T21:12:05Z
- **Test source:** test/test_nilpy_getattr_with_a_literal_name_names_a_method.npy test/test_nilpy_getattr_with_a_literal_name_names_a_method.expected
- **Failing step:** line 1 of 27 of the job's recipe; it names `test/test_nilpy_getattr_with_a_literal_name_names_a_method.npy`.
  ```
  ./compiler/pascal26 test/test_nilpy_getattr_with_a_literal_name_names_a_method.npy /tmp/test_nilpy_getattrlit26
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_getattr_with_a_literal_name_names_a_method.npy'` at 844ccea7a0f2d80521a71d1c58d65cc0d2d1ef4b

## Range
> **The named sha `844ccea7a0f2` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `844ccea7a0f2`, last good `ff6694727a23`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:67: error: no overload of e matches these arguments
(tail)
pascal26:67: error: no overload of e matches these arguments
  argument types: (Integer, Integer)
  candidates:
    e()
  near: e ( 1 , 1 ) >>> )  print 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-09-29 — resolved, commit efa290f3e4.
