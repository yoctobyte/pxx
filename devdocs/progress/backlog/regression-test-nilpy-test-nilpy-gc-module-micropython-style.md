---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The failing step (line 2 of 3) named no source of its own, but this job has only ONE source — so first-source and only-source are the same file here and there is no other lane in frame. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# first-ever red: test-nilpy#src:test/test_nilpy_gc_module_micropython_style.py@3 at 759c3fe03246 in step 2/3, `for o in c3 s3; do nm /tmp/test_nilpy_gc_$o.o | grep -q ' U heap_caps_get_free_size' || { echo "FAIL: nilpy gc on $o do…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `97528b18bd0f`).
  Untriaged.
- **Found:** 2026-10-11T11:21:53Z
- **Test source:** test/test_nilpy_gc_module_micropython_style.py
- **Failing step:** line 2 of 3 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  for o in c3 s3; do nm /tmp/test_nilpy_gc_$o.o | grep -q ' U heap_caps_get_free_size' || { echo "FAIL: nilpy gc on $o does not read IDF's heap"; exit 1; }; done
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_gc_module_micropython_style.py@3'` at 759c3fe032469ccec43eb253a3b18588be6b2c45

## Range
bad `759c3fe03246`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
nm: '/tmp/testmgr-scratch-1124144/test_nilpy_gc_c3.o': No such file
FAIL: nilpy gc on c3 does not read IDF's heap

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
