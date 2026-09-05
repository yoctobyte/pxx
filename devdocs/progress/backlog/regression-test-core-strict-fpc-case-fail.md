---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 6 of 15, `! ./compiler/pascal26 test/test_record_class_var_fail.pas /tmp/test_rcv26 > /tmp/test_rcv.log 2>&1`, which names `test/test_record_class_var_fail.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 7 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This expectation records a REFUSAL** (a *_fail / {%FAIL} test). Before treating a converged bisect range as an accusation, check whether the named commit IMPLEMENTED the thing being refused -- a feature landing makes its own refusal test go red, and the bisect converges on it correctly. Not a verdict; the tool cannot decide this one.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/strict_fpc_case_fail.pas at f2c6ff3288b4 in step 6/15, `! ./compiler/pascal26 test/test_record_class_var_fail.pas /tmp/test_rcv26 > /tmp/test_rcv.log 2>&1` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-05T18:04:58Z
- **Test source:** test/strict_fpc_case_fail.pas test/test_record_self_field_fail.pas +5
- **Failing step:** line 6 of 15 of the job's recipe; it names `test/test_record_class_var_fail.pas`.
  ```
  ! ./compiler/pascal26 test/test_record_class_var_fail.pas /tmp/test_rcv26 > /tmp/test_rcv.log 2>&1
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/strict_fpc_case_fail.pas'` at f2c6ff3288b407ca08ee7e469f4b2a8b56f98972

## Range
> **The named sha `f2c6ff3288b4` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `f2c6ff3288b4`, last good `7867c5481c01`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
