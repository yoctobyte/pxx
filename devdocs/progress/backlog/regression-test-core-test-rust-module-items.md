---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 16 of 5 is `./compiler/pascal26 /tmp/rust_unity.rs /tmp/test_rust_unity26`. The job's own `src` (`test/test_rust_module_items.rs`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_rust_module_items.rs at 99af5f3270cf in step 16/5, `./compiler/pascal26 /tmp/rust_unity.rs /tmp/test_rust_un` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-08-31T15:49:17Z
- **Test source:** test/test_rust_module_items.rs tools/expect_same.sh +1
- **Failing step:** line 16 of 5 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  ./compiler/pascal26 /tmp/rust_unity.rs /tmp/test_rust_unity26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_rust_module_items.rs'` at 99af5f3270cfd1a2f36857c6d46bc5863a21d6e8

## Range
> **The named sha `99af5f3270cf` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `99af5f3270cf`, last good `2bdb3c4ef3f6`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:41: error: Unsupported operator in IR codegen
(tail)
ok: /tmp/testmgr-scratch-2230407/test_rust_mitems26  [code=3864B  data=560B  bss=33619B  procs=4]
pascal26:41: error: Unsupported operator in IR codegen
  near:    n   >>>  Board  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
