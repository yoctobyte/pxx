---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 4, `./compiler/pascal26 test/test_char_to_pchar_conversion.pas /tmp/test_ctp26`, which names `test/test_char_to_pchar_conversion.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 5 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_char_to_pchar_conversion.pas at f2c6ff3288b4 in step 1/4, `./compiler/pascal26 test/test_char_to_pchar_conversion.pas /tmp/test_ctp26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-05T18:04:59Z
- **Test source:** test/test_char_to_pchar_conversion.pas tools/expect_same.sh +3
- **Failing step:** line 1 of 4 of the job's recipe; it names `test/test_char_to_pchar_conversion.pas`.
  ```
  ./compiler/pascal26 test/test_char_to_pchar_conversion.pas /tmp/test_ctp26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_char_to_pchar_conversion.pas'` at f2c6ff3288b407ca08ee7e469f4b2a8b56f98972

## Range
> **The named sha `f2c6ff3288b4` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `f2c6ff3288b4`, last good `7867c5481c01`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:78: error: no overload of Show matches these arguments
pascal26:82: error: no overload of D matches these arguments
pascal26:83: error: no overload of E matches these arguments
pascal26:84: error: no overload of F matches these arguments
(tail)
pascal26:78: error: no overload of Show matches these arguments
  argument types: (Char)
  candidates:
    Show(Pointer)
  near: ; begin Show ( '-' ) >>> ; Show ( 
pascal26:78: error: no overload of Show matches these arguments
  argument types: (Char)
  candidates:
    Show(Pointer)
  near: ) ; Show ( #45 ) >>> ; Show ( 
pascal26:78: error: no overload of Show matches these arguments
  argument types: (Char)
  candidates:
    Show(Pointer)
  near: ) ; Show ( Dash ) >>> ; Show ( 
pascal26:78: error: no overload of Show matches these arguments
  argument types: (Char)
  candidates:
    Show(Pointer)
  near: ( Chr ( 45 ) ) >>> ; Show ( 
pascal26:78: error: no overload of Show matches these arguments
  argument types: (Char)
  candidates:
    Show(Pointer)
  near: ( Chr ( K ) ) >>> ; WriteLn ( 
pascal26:82: error: no overload of D matches these arguments
  argument types: (Char)
  candidates:
    D(Pointer)
  near: ) ; D ( 'z' ) >>> ; E ( 
pascal26:83: error: no overload of E matches these arguments
  argument types: (Integer, Char)
  candidates:
    E(Integer, Pointer)
  near: E ( 2 , 'y' ) >>> ; r := 
pascal26:84: error: no overload of F matches these arguments
  argument types: (Char)
  candidates:
    F(Pointer)
  near: r := F ( 'q' ) >>> ; o := 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-05 — auto-closed by the seven watcher: `test-core#src:test/test_char_to_pchar_conversion.pas` passes at 2d6bfadd6025 (tier native); it was red at f2c6ff3288b4. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
