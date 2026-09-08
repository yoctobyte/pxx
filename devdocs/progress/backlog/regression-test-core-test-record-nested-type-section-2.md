---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_record_nested_type_section.pas /tmp/test_rnts26`, which names `test/test_record_nested_type_section.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_record_nested_type_section.pas at d81b90a991e9 in step 1/2, `./compiler/pascal26 test/test_record_nested_type_section.pas /tmp/test_rnts26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5666dc9dba23`).
  Untriaged.
- **Found:** 2026-09-08T07:02:22Z
- **Test source:** test/test_record_nested_type_section.pas tools/expect_same.sh +1
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_record_nested_type_section.pas`.
  ```
  ./compiler/pascal26 test/test_record_nested_type_section.pas /tmp/test_rnts26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_record_nested_type_section.pas'` at d81b90a991e9eb2266c31c9d2f3889173c7ab8df

## Range
bad `d81b90a991e9`, last good `baad7e842cd8`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:100: error: "Q": no such member on this record/class
(tail)
pascal26:100: error: "Q": no such member on this record/class
  near: . Sum ) ; t . >>> Q := 4 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
