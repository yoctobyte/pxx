---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 3, `./compiler/pascal26 -dPXX_ALLOC_CENSUS test/test_generator_instance_freed_on_escaping_raise.pas /tmp/test_gifer26`, which names `test/test_generator_instance_freed_on_escaping_raise.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_generator_instance_freed_on_escaping_raise.pas at f2c6ff3288b4 in step 1/3, `./compiler/pascal26 -dPXX_ALLOC_CENSUS test/test_generator_instance_freed_on_escaping_raise.pas /tmp/test_gifer26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-05T18:04:59Z
- **Test source:** test/test_generator_instance_freed_on_escaping_raise.pas tools/expect_same.sh +1
- **Failing step:** line 1 of 3 of the job's recipe; it names `test/test_generator_instance_freed_on_escaping_raise.pas`.
  ```
  ./compiler/pascal26 -dPXX_ALLOC_CENSUS test/test_generator_instance_freed_on_escaping_raise.pas /tmp/test_gifer26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_generator_instance_freed_on_escaping_raise.pas'` at f2c6ff3288b407ca08ee7e469f4b2a8b56f98972

## Range
> **The named sha `f2c6ff3288b4` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `f2c6ff3288b4`, last good `7867c5481c01`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:77: error: incompatible types: cannot assign Int64 to Pointer
(tail)
pascal26:77: error: incompatible types: cannot assign Int64 to Pointer

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
