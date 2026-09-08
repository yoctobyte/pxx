---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_a_nested_type_may_specialize_its_own_template.pas /tmp/test_selfnesttype26`, which names `test/test_a_nested_type_may_specialize_its_own_template.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_a_nested_type_may_specialize_its_own_template.pas at 630c8d31c63a in step 1/2, `./compiler/pascal26 test/test_a_nested_type_may_specialize_its_own_template.pas /tmp/test_selfnesttype26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5666dc9dba23`).
  Untriaged.
- **Found:** 2026-09-08T03:35:08Z
- **Test source:** test/test_a_nested_type_may_specialize_its_own_template.pas tools/expect_same.sh +1
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_a_nested_type_may_specialize_its_own_template.pas`.
  ```
  ./compiler/pascal26 test/test_a_nested_type_may_specialize_its_own_template.pas /tmp/test_selfnesttype26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_a_nested_type_may_specialize_its_own_template.pas'` at 630c8d31c63aac9bc7122cab5126833a66778378

## Range
bad `630c8d31c63a`, last good `ff845093f28f`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:94: error: class method not found (TSelfParam)
pascal26:94: error: a statement cannot start with '.'
(tail)
pascal26:94: error: class method not found (TSelfParam)
  near: ; viaParam := TI . TSelfParam >>> . Create ; 
pascal26:94: error: a statement cannot start with '.'
  near: := TI . TSelfParam . Create >>> ; viaParam . 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
