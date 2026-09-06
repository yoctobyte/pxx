---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_a_named_dynamic_array_parameter_still_takes_nil_as_a_default.pas /tmp/test_dynarraydefault`, which names `test/test_a_named_dynamic_array_parameter_still_takes_nil_as_a_default.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_a_named_dynamic_array_parameter_still_takes_nil_as_a_default.pas at fc43936b00d9 in step 1/2, `./compiler/pascal26 test/test_a_named_dynamic_array_parameter_still_takes_nil_as_a_default.pas /tmp/test_dynarraydefaul…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T11:19:49Z
- **Test source:** test/test_a_named_dynamic_array_parameter_still_takes_nil_as_a_default.pas tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_a_named_dynamic_array_parameter_still_takes_nil_as_a_default.pas`.
  ```
  ./compiler/pascal26 test/test_a_named_dynamic_array_parameter_still_takes_nil_as_a_default.pas /tmp/test_dynarraydefault26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_a_named_dynamic_array_parameter_still_takes_nil_as_a_default.pas'` at fc43936b00d9c032757157762ac2adf344b22407

## Range
> **The named sha `fc43936b00d9` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `fc43936b00d9`, last good `847091ba8c13`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:40: error: a parameter of an open-array or fixed-array type cannot have a default value: there is no array literal to write there, so the value would be a scalar whose bytes the callee reads as a length header. A named DYNAMIC array type takes a default (`a: TArr = nil`) because it is a handle (bug-a-managed-string-arg-temp-predicate-is-duplicated-seven-times-and-guarded-nowhere)
(tail)
pascal26:40: error: a parameter of an open-array or fixed-array type cannot have a default value: there is no array literal to write there, so the value would be a scalar whose bytes the callee reads as a length header. A named DYNAMIC array type takes a default (`a: TArr = nil`) because it is a handle (bug-a-managed-string-arg-temp-predicate-is-duplicated-seven-times-and-guarded-nowhere)
  near: ( const a : TArr = >>> nil ) ; 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-06 — auto-closed by the seven watcher: `test-core#src:test/test_a_named_dynamic_array_parameter_still_takes_nil_as_a_default.pas` passes at 6d72805b066c (tier native); it was red at fc43936b00d9. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
