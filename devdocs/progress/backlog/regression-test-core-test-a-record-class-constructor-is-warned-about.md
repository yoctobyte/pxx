---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_a_record_class_constructor_is_warned_about.pas /tmp/test_recclassctorwarn26 > /tmp/recclas`, which names `test/test_a_record_class_constructor_is_warned_about.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 1 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# first-ever red: test-core#src:test/test_a_record_class_constructor_is_warned_about.pas at ad2735420d6b in step 1/2, `./compiler/pascal26 test/test_a_record_class_constructor_is_warned_about.pas /tmp/test_recclassctorwarn26 > /tmp/reccla…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T09:42:27Z
- **Test source:** test/test_a_record_class_constructor_is_warned_about.pas
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_a_record_class_constructor_is_warned_about.pas`.
  ```
  ./compiler/pascal26 test/test_a_record_class_constructor_is_warned_about.pas /tmp/test_recclassctorwarn26 > /tmp/recclassctorwarn.log 2>&1
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_a_record_class_constructor_is_warned_about.pas'` at ad2735420d6b85ae25863b82ab3b591ca0282b31

## Range
> **The named sha `ad2735420d6b` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `ad2735420d6b`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
