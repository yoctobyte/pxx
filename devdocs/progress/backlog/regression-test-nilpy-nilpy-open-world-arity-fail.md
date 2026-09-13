---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 1 of 11, `./compiler/pascal26 test/nilpy_open_world_arity_fail.npy /tmp/nilpy_ow_ar26 2>&1 \ | grep -q "takes at most 4 arguments"`, which names `test/nilpy_open_world_arity_fail.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This expectation records a REFUSAL** (a *_fail / {%FAIL} test). Before treating a converged bisect range as an accusation, check whether the named commit IMPLEMENTED the thing being refused -- a feature landing makes its own refusal test go red, and the bisect converges on it correctly. Not a verdict; the tool cannot decide this one.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/nilpy_open_world_arity_fail.npy at 95e7eb26e171 in step 1/11, `./compiler/pascal26 test/nilpy_open_world_arity_fail.npy /tmp/nilpy_ow_ar26 2>&1 \ | grep -q "takes at most 4 arguments…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-13T16:47:25Z
- **Test source:** test/nilpy_open_world_arity_fail.npy test/test_nilpy_package_imports.npy +1
- **Failing step:** line 1 of 11 of the job's recipe; it names `test/nilpy_open_world_arity_fail.npy`.
  ```
  ./compiler/pascal26 test/nilpy_open_world_arity_fail.npy /tmp/nilpy_ow_ar26 2>&1 \ | grep -q "takes at most 4 arguments" \ || { echo 'nilpy_open_world_arity_fail: FAIL - a fifth positional argument must be refused, not dropped'; exit 1; }
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/nilpy_open_world_arity_fail.npy'` at 95e7eb26e171d8452452d5f4b0856306456fff78

## Range
bad `95e7eb26e171`, last good `c21e1edc4598`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
nilpy_open_world_arity_fail: FAIL - a fifth positional argument must be refused, not dropped

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
