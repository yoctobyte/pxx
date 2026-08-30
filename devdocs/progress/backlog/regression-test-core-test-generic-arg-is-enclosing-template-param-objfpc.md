---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 11 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_generic_arg_is_enclosing_template_param_objfpc.pas red at 1d8b44e59042 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-30T02:19:22Z
- **Test source:** test/test_generic_arg_is_enclosing_template_param_objfpc.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_generic_arg_is_enclosing_template_param_objfpc.pas'` at 1d8b44e590426d333f7936404e0235b83ccdf7af

## Range
> **The named sha `1d8b44e59042` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `1d8b44e59042`, last good `0bcef8f3f2ab`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:16: error: unknown type: TKey
(tail)
pascal26:16: error: unknown type: TKey
  near: TKey   class Val  >>> TKey  end 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
