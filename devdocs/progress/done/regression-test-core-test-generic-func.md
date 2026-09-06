---
prio: 70
track: P
status: done
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_generic_func.pas /tmp/test_generic_func26`, which names `test/test_generic_func.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_generic_func.pas at b2a41d5f4fb9 in step 1/2, `./compiler/pascal26 test/test_generic_func.pas /tmp/test_generic_func26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T16:20:47Z
- **Test source:** test/test_generic_func.pas tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_generic_func.pas`.
  ```
  ./compiler/pascal26 test/test_generic_func.pas /tmp/test_generic_func26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_generic_func.pas'` at b2a41d5f4fb93afe09b23d1b7ee3999eaa906523

## Range
> **The named sha `b2a41d5f4fb9` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b2a41d5f4fb9`, last good `29c40526f145`, 9 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:26: error: expected 'begin' before 'Max_Integer'
(tail)
pascal26:26: error: expected 'begin' before 'Max_Integer'
  near: B := tmp ; end ; >>> Max_Integer as MaxIntF 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


## Resolution — 2026-09-06, frankD. Cause: eb2447470, and the `(` it removed was ACCIDENTAL COVER.

`eb2447470` correctly stopped the call-site predicate in
`SpecializeInlineGenericFuncUses` from requiring a trailing `(` on the
**keyword** surface: `specialize DoTest<TTest>` is a parameterless call and the
`(` was a proxy for "this is not a comparison chain", which the keyword already
settles. That reasoning is sound and the fix stays.

**What it could not see is that the `(` was doing a second, undocumented job.**
`specialize Max<Integer> as MaxIntF;` is the specialization-ALIAS DECLARATION,
and it differs from a parameterless call by exactly one token — `as` where a
call has `(`. With the `(` no longer required, the call-site sweep matched the
declaration, rewrote the run to `Max_Integer` and consumed the keyword, leaving
`Max_Integer as MaxIntF;` where a declaration had been. The reader then said
`expected 'begin' before 'Max_Integer'` — **a complaint about the declaration
section ending, three phases after the rewrite that caused it.**

Nothing recorded that second job. The guard's own comment described the
comparison chain alone, and the `isDecl` check beside it covers only the OTHER
declaration shape (a `function`/`procedure` header) — it had exactly the same
character and was documented, which is the difference.

**Fix:** the no-parens allowance now excludes a following `as`. This restores
the pre-eb2447470 behaviour for the alias form exactly — it required `(` then
too, so a genuine `specialize F<T> as TFoo` cast of a parameterless call did
not work before and does not work now. Unchanged, not newly refused.

**Why the author's gate did not catch it:** `gate.sh quick` does not run
`test-core`, and the two rows that cover the alias form — this one and
`test_inline_generic_specialization` — live there. The fixture eb2447470 added is an fpc
differential and **cannot** carry the alias form, because fpc rejects it
(`Syntax error, "BEGIN" expected but "identifier SPECIALIZE" found`) — it is a
pxx extension. So the two spellings the predicate must tell apart are
necessarily in two files. Each now names the other, and the parameterless
fixture says explicitly to run both.

Verified: both rows GREEN under `testmgr --tier native`; eb2447470's own fixture
still GREEN; `tgenfunc12.pp`, the corpus row it un-skipped, still compiles and
runs exit 0; `tgenfunc19.pp` still stops at :32 with `undefined variable
(TTest2)`, the wall its corrected skip reason names — unchanged.
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 8d37fac6b.
