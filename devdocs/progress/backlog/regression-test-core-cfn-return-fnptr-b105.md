---
prio: 70
track: C
---

> **Track guessed as C from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/cfn_return_fnptr_b105.c /tmp/cfn_return_fnptr_b10526`, which names `test/cfn_return_fnptr_b105.c`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/cfn_return_fnptr_b105.c at 65b719ab48ae in step 1/2, `./compiler/pascal26 test/cfn_return_fnptr_b105.c /tmp/cfn_return_fnptr_b10526` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-02T00:40:16Z
- **Test source:** test/cfn_return_fnptr_b105.c tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/cfn_return_fnptr_b105.c`.
  ```
  ./compiler/pascal26 test/cfn_return_fnptr_b105.c /tmp/cfn_return_fnptr_b10526
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/cfn_return_fnptr_b105.c'` at 65b719ab48ae3a2af0ba5acea881cbb891fe6eca

## Range
> **The named sha `65b719ab48ae` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `65b719ab48ae`, last good `49d0ac95f76d`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:21: error: C function definition: more than 16 parameters not supported (MAX_PROC_PARAMS)
(tail)
pascal26:21: error: C function definition: more than 16 parameters not supported (MAX_PROC_PARAMS)
  near: z      >>>   v 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
