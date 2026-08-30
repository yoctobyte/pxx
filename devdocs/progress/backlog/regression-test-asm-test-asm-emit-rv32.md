---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-asm#src:test/test_asm_emit_rv32.pas red at 108ac182bed6 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T05:56:04Z
- **Test source:** test/test_asm_emit_rv32.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-asm#src:test/test_asm_emit_rv32.pas'` at 108ac182bed6cd40244fd24108d6664d6cf1b2f0

## Range
> **The named sha `108ac182bed6` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `108ac182bed6`, last good `c951ec710b33`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:43: error: undefined variable (AIntToStr)
pascal26:44: error: expected comma or close parenthesis
(tail)
pascal26:43: error: undefined variable (AIntToStr)
  in: compiler/rv32enc.inc
  near:  what   displacement   AIntToStr >>>  v  
pascal26:44: error: expected comma or close parenthesis
  in: compiler/rv32enc.inc
  near: v    is outside the encodable range   AIntToStr >>>  lo  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
