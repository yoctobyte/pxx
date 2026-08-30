---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-asm#src:test/test_asm_emit_x64.pas red at 94492d162332 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T12:18:06Z
- **Test source:** test/test_asm_emit_x64.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-asm#src:test/test_asm_emit_x64.pas'` at 94492d162332c9dc40bc84b11d1ae8bc467d7c6c

## Range
> **The named sha `94492d162332` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `94492d162332`, last good `3fd296c6b38d`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:1040: error: undefined variable (LibcSyscallCallCount)
pascal26:1052: error: undefined variable (PxxDbgWants)
pascal26:1075: error: undefined variable (PxxDbgWants)
(tail)
pascal26:1040: error: undefined variable (LibcSyscallCallCount)
  in: compiler/asmtext.inc
  near:  FixCount  s0  LibcSyscallCallCount >>>  AsmTextLine  
pascal26:1052: error: undefined variable (PxxDbgWants)
  in: compiler/asmtext.inc
  near: AsmMemoPoison    if PxxDbgWants >>>  a.asmmemo  
pascal26:1075: error: undefined variable (PxxDbgWants)
  in: compiler/asmtext.inc
  near: AsmMemoReport  begin if not PxxDbgWants >>>  a.asmmemo  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
