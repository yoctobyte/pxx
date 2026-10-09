---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 3 of 6, `! ./compiler/pascal26 test/test_nilpy_dataclass_frozen_fail.npy /tmp/test_nilpy_dcfrozen26 > /tmp/test_nilpy_dcfrozen.lo`, which names `test/test_nilpy_dataclass_frozen_fail.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 4 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **The SLUG names `test_nilpy_dataclass_order`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `test_nilpy_dataclass_frozen_fail`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_dataclass_order.npy at 39225dde3632 in step 3/6, `! ./compiler/pascal26 test/test_nilpy_dataclass_frozen_fail.npy /tmp/test_nilpy_dcfrozen26 > /tmp/test_nilpy_dcfrozen.l…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `97528b18bd0f`).
  Untriaged.
- **Found:** 2026-10-09T14:31:59Z
- **Test source:** test/test_nilpy_dataclass_order.npy test/test_nilpy_dataclass_order.expected +2
- **Failing step:** line 3 of 6 of the job's recipe; it names `test/test_nilpy_dataclass_frozen_fail.npy`.
  ```
  ! ./compiler/pascal26 test/test_nilpy_dataclass_frozen_fail.npy /tmp/test_nilpy_dcfrozen26 > /tmp/test_nilpy_dcfrozen.log 2>&1
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_dataclass_order.npy'` at 39225dde36328946c03caed301e220c9962173a8

## Range
bad `39225dde3632`, last good `62fc7c1e802a`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-203328/test_nilpy_dcorder26  [code=555744B  data=114456B  bss=69524B  procs=2397  codeseg=556768B]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
