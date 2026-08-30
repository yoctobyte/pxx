---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-asm#src:test/test_asm_emit_x64.pas red at 31198d3674df (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T05:08:12Z
- **Test source:** test/test_asm_emit_x64.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-asm#src:test/test_asm_emit_x64.pas'` at 31198d3674dfe530aa0699f0eb775346a705410a

## Range
> **The named sha `31198d3674df` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `31198d3674df`, last good `7956dc38005e`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:193: error: undefined variable (EmitSyscall)
(tail)
pascal26:193: error: undefined variable (EmitSyscall)
  in: compiler/x64enc.inc
  near:    end else EmitSyscall >>>  end  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
