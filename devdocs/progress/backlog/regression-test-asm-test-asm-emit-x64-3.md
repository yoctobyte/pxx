---
prio: 70
track: A
---

> **Track A from the job NAME `test-asm`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/test_asm_emit_x64.pas`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-asm#src:test/test_asm_emit_x64.pas at a0c5a21e2c2e in step 1/2, `./compiler/pascal26 -Fucompiler test/test_asm_emit_x64.p` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-09-01T02:53:40Z
- **Test source:** test/test_asm_emit_x64.pas tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_asm_emit_x64.pas`.
  ```
  ./compiler/pascal26 -Fucompiler test/test_asm_emit_x64.pas /tmp/sweep_asmemit_x6426
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-asm#src:test/test_asm_emit_x64.pas'` at a0c5a21e2c2eb04f63554d4801e1655e2c548f3c

## Range
> **The named sha `a0c5a21e2c2e` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `a0c5a21e2c2e`, last good `c04a6666bdd7`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:1088: error: undefined variable (PxxDbgArg)
pascal26:1089: error: undefined variable (DwArmsOff)
pascal26:1091: error: undefined variable (DwTotalCalls)
pascal26:1092: error: undefined variable (DwElseHits)
pascal26:1092: error: undefined variable (DwElseAns)
pascal26:1093: error: undefined variable (DwBackHits)
pascal26:1093: error: undefined variable (DwBackAns)
(tail)
pascal26:1088: error: undefined variable (PxxDbgArg)
  in: compiler/asmtext.inc
  near: n do begin if items [ >>> i ] . 
pascal26:1089: error: undefined variable (DwArmsOff)
  in: compiler/asmtext.inc
  near: <> vtAnsiString then Error ( 'EmitAsmX64: expected an instruction string' >>> ) ; line 
pascal26:1091: error: undefined variable (DwTotalCalls)
  in: compiler/asmtext.inc
  near: ( items [ i ] . >>> VAnsiString ) ; 
pascal26:1092: error: undefined variable (DwElseHits)
  in: compiler/asmtext.inc
  near: ] . VAnsiString ) ; trimmed >>> := AsmTextTrim ( 
pascal26:1092: error: undefined variable (DwElseAns)
  in: compiler/asmtext.inc
  near: ; trimmed := AsmTextTrim ( line >>> ) ; j 
pascal26:1093: error: undefined variable (DwBackHits)
  in: compiler/asmtext.inc
  near: ( line ) ; j := >>> 1 ; while 
pascal26:1093: error: undefined variable (DwBackAns)
  in: compiler/asmtext.inc
  near: j := 1 ; while ( >>> j <= Length 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
