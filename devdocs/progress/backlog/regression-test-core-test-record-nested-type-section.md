---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_record_nested_type_section.pas /tmp/test_rnts26`, which names `test/test_record_nested_type_section.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_record_nested_type_section.pas at 6e00f29b0d93 in step 1/2, `./compiler/pascal26 test/test_record_nested_type_section.pas /tmp/test_rnts26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-05T22:09:44Z
- **Test source:** test/test_record_nested_type_section.pas tools/expect_same.sh +1
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_record_nested_type_section.pas`.
  ```
  ./compiler/pascal26 test/test_record_nested_type_section.pas /tmp/test_rnts26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_record_nested_type_section.pas'` at 6e00f29b0d93c1de28a173ae8867c7f08dd0b3e3

## Range
> **The named sha `6e00f29b0d93` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `6e00f29b0d93`, last good `10fa2709d830`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:87: error: unknown type: TAlias
(tail)
pascal26:87: error: unknown type: TAlias
  near: TSubCls ; a : TOuterR . >>> TAlias ; cl 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
