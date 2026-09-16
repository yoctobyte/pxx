---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 3 of 12, `./compiler/pascal26 test/test_nilpy_subscript_dunder_spellings.npy /tmp/test_nilpy_subdunder26`, which names `test/test_nilpy_subscript_dunder_spellings.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 4 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **The SLUG names `test_nilpy_builtin_subclass_dunder_dispatch`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `test_nilpy_subscript_dunder_spellings`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_builtin_subclass_dunder_dispatch.npy at 5dbee723e228 in step 3/12, `./compiler/pascal26 test/test_nilpy_subscript_dunder_spellings.npy /tmp/test_nilpy_subdunder26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-16T01:17:27Z
- **Test source:** test/test_nilpy_builtin_subclass_dunder_dispatch.npy tools/expect_same.sh +2
- **Failing step:** line 3 of 12 of the job's recipe; it names `test/test_nilpy_subscript_dunder_spellings.npy`.
  ```
  ./compiler/pascal26 test/test_nilpy_subscript_dunder_spellings.npy /tmp/test_nilpy_subdunder26
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_builtin_subclass_dunder_dispatch.npy'` at 5dbee723e228cfb986a5561e78ccffb7e9a153ec

## Range
bad `5dbee723e228`, last good `1704e17de6f3`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:40: error: no overload of get matches these arguments
(tail)
ok: /tmp/testmgr-scratch-3707340/test_nilpy_subdunder26  [code=1351448B  data=89418B  bss=55340B  procs=2201]
pascal26:40: error: no overload of get matches these arguments
  argument types: (class, AnsiString)
  candidates:
    get(Variant, Int64)
  near: : 1 } , 'a' ) >>> )  print 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
