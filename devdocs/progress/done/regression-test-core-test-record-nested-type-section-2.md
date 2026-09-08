---
prio: 70
track: P
status: done
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_record_nested_type_section.pas /tmp/test_rnts26`, which names `test/test_record_nested_type_section.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_record_nested_type_section.pas at d81b90a991e9 in step 1/2, `./compiler/pascal26 test/test_record_nested_type_section.pas /tmp/test_rnts26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5666dc9dba23`).
  Untriaged.
- **Found:** 2026-09-08T07:02:22Z
- **Test source:** test/test_record_nested_type_section.pas tools/expect_same.sh +1
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_record_nested_type_section.pas`.
  ```
  ./compiler/pascal26 test/test_record_nested_type_section.pas /tmp/test_rnts26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_record_nested_type_section.pas'` at d81b90a991e9eb2266c31c9d2f3889173c7ab8df

## Range
bad `d81b90a991e9`, last good `baad7e842cd8`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:100: error: "Q": no such member on this record/class
(tail)
pascal26:100: error: "Q": no such member on this record/class
  near: . Sum ) ; t . >>> Q := 4 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Verified dead at HEAD (2026-09-08, frankS)

Same cause and same fix as
[[regression-test-core-test-nested-class-type-scoping]] -- `d81b90a99` stripped a
qualified type prefix ahead of `ParseTypeKindInner`'s own copy of that strip,
which is the copy that rewrites a nested class or record name to its registered
row. `5ea212e36` narrows the strip to array members, where the two copies
provably agree.

**AFTER only, in this checkout, and the BEFORE stays the watcher's.** At
`5ea212e36`, compiler `29e343715a4a`, this source is byte-identical to
`test/test_record_nested_type_section.expected` (11 rows). I have no local
control for it FAILING at `d81b90a99`: `test-core` stops at the first failure and
my run died on `test_nested_class_type_scoping` before reaching this one. That it
was red then is host seven's measurement, not mine, and is recorded here as
seven's rather than restated as if I had reproduced it.
- 2026-09-08 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
- 2026-09-08 — verified dead at HEAD 5ea212e36 (compiler 29e343715a4a) and closed by frankS; the fix is 5ea212e36, the cause was 5ea212e36's parent d81b90a99.
