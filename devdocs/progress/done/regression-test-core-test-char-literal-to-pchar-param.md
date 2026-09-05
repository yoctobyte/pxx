---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 -Fulib/rtl test/test_char_literal_to_pchar_param.pas /tmp/test_charlitpchar26`, which names `test/test_char_literal_to_pchar_param.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_char_literal_to_pchar_param.pas at f2c6ff3288b4 in step 1/2, `./compiler/pascal26 -Fulib/rtl test/test_char_literal_to_pchar_param.pas /tmp/test_charlitpchar26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-05T18:04:59Z
- **Test source:** test/test_char_literal_to_pchar_param.pas tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_char_literal_to_pchar_param.pas`.
  ```
  ./compiler/pascal26 -Fulib/rtl test/test_char_literal_to_pchar_param.pas /tmp/test_charlitpchar26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_char_literal_to_pchar_param.pas'` at f2c6ff3288b407ca08ee7e469f4b2a8b56f98972

## Range
> **The named sha `f2c6ff3288b4` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `f2c6ff3288b4`, last good `7867c5481c01`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:109: error: no overload of Show matches these arguments
pascal26:110: error: no overload of Show matches these arguments
pascal26:111: error: no overload of Show matches these arguments
pascal26:122: error: no overload of Mid matches these arguments
pascal26:122: error: no overload of Show matches these arguments
pascal26:148: error: no overload of StrCopy matches these arguments
pascal26:149: error: no overload of StrCat matches these arguments
pascal26:151: error: no overload of StrLen matches these arguments
(tail)
pascal26:109: error: no overload of Show matches these arguments
  argument types: (ShortString, Char)
  candidates:
    Show(AnsiString, Pointer)
  near: Show ( 'one-char literal' , '-' ) >>> ; Show ( 
pascal26:110: error: no overload of Show matches these arguments
  argument types: (ShortString, Char)
  candidates:
    Show(AnsiString, Pointer)
  near: Show ( 'a #45 literal' , #45 ) >>> ; Show ( 
pascal26:111: error: no overload of Show matches these arguments
  argument types: (ShortString, Char)
  candidates:
    Show(AnsiString, Pointer)
  near: Show ( 'a named char const' , Dash ) >>> ; ChkS ( 
pascal26:122: error: no overload of Mid matches these arguments
  argument types: (Char)
  candidates:
    Mid(Pointer)
  near: 'a call result of a one-char literal' , Mid ( '-' ) >>> ) ; obj 
pascal26:122: error: no overload of Show matches these arguments
  argument types: (ShortString, Integer)
  candidates:
    Show(AnsiString, Pointer)
  near: , Mid ( '-' ) ) >>> ; obj := 
pascal26:148: error: no overload of StrCopy matches these arguments
  argument types: (Pointer, Char)
  candidates:
    StrCopy(Pointer, Pointer)
  near: [ 0 ] , 'x' ) >>> ; StrCat ( 
pascal26:149: error: no overload of StrCat matches these arguments
  argument types: (Pointer, Char)
  candidates:
    StrCat(Pointer, Pointer)
  near: [ 0 ] , '-' ) >>> ; ChkS ( 
pascal26:151: error: no overload of StrLen matches these arguments
  argument types: (Char)
  candidates:
    StrLen(Pointer)
  near: IntToStr ( StrLen ( '-' ) >>> ) , '1' 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-05 — auto-closed by the seven watcher: `test-core#src:test/test_char_literal_to_pchar_param.pas` passes at 2d6bfadd6025 (tier native); it was red at f2c6ff3288b4. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
