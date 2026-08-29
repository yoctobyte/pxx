---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 10 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_min_max_variadic.npy red at 1d98cf21375f (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-29T16:55:03Z
- **Test source:** test/test_nilpy_min_max_variadic.npy tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_min_max_variadic.npy'` at 1d98cf21375ff1166329c5568643600aa63ece72

## Range
> **The named sha `1d98cf21375f` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `1d98cf21375f`, last good `154d1aa3fba6`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:8: error: Nil Python: no 2-argument ( for these operand types
(tail)
pascal26:8: error: Nil Python: no 2-argument ( for these operand types
  near:  max     >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
