---
prio: 70
track: A
---

> **Track A from the job NAME `test-aarch64`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/test_rtti.pas`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 13 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-aarch64#src:test/test_rtti.pas at 9d5a4e27029e in step 1/3, `./compiler/pascal26 -dPXX_MANAGED_STRING --target=aarch64 test/test_rtti.pas /tmp/test_aarch64_rtti` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-04T18:15:00Z
- **Test source:** test/test_rtti.pas tools/expect_same.sh +1
- **Failing step:** line 1 of 3 of the job's recipe; it names `test/test_rtti.pas`.
  ```
  ./compiler/pascal26 -dPXX_MANAGED_STRING --target=aarch64 test/test_rtti.pas /tmp/test_aarch64_rtti
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-aarch64#src:test/test_rtti.pas'` at 9d5a4e27029eb30dd509ad8ab8326b269a8b9af7

## Range
> **The named sha `9d5a4e27029e` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `9d5a4e27029e`, last good `b040c90e6c8b`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:144: error: no overload of SetMethodProp matches these arguments
(tail)
pascal26:144: error: no overload of SetMethodProp matches these arguments
  argument types: (Pointer, Pointer, record)
  candidates:
    SetMethodProp(Pointer, Pointer, record)
  near: ) , p , meth ) >>> ; meth := 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
