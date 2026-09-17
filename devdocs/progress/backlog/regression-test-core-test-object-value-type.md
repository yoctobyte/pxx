---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 8 of 9, `! ./compiler/pascal26 test/test_object_value_constructor_error.pas /tmp/test_object_value_constructor_error26 > /tmp/tes`, which names `test/test_object_value_constructor_error.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 5 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **The SLUG names `test_object_value_type`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `test_object_value_constructor_error`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_object_value_type.pas at cc03b4a51933 in step 8/9, `! ./compiler/pascal26 test/test_object_value_constructor_error.pas /tmp/test_object_value_constructor_error26 > /tmp/te…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-17T16:06:33Z
- **Test source:** test/test_object_value_type.pas tools/expect_same.sh +3
- **Failing step:** line 8 of 9 of the job's recipe; it names `test/test_object_value_constructor_error.pas`.
  ```
  ! ./compiler/pascal26 test/test_object_value_constructor_error.pas /tmp/test_object_value_constructor_error26 > /tmp/test_object_value_constructor_error.log 2>&1
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_object_value_type.pas'` at cc03b4a51933a51b3e30c3334797c209f534504f

## Range
> **The named sha `cc03b4a51933` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `cc03b4a51933`, last good `d0cad59b99e3`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-46993/test_object_value_type26  [code=73496B  data=4832B  bss=46660B  procs=152]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
