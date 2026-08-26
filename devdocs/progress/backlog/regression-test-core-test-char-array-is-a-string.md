---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_char_array_is_a_string.pas red at 357217a73608 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-26T13:01:56Z
- **Test source:** test/test_char_array_is_a_string.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_char_array_is_a_string.pas'` at 357217a73608b10ffa0eb976c126a691c790c4eb

## Range
> **The named sha `357217a73608` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `357217a73608`, last good `902e53050f07`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:111: error: no overload of Wrap matches these arguments
pascal26:111: error: no overload of ChkS matches these arguments
pascal26:112: error: no overload of WrapV matches these arguments
(tail)
pascal26:111: error: no overload of Wrap matches these arguments
  argument types: (Char)
  candidates:
    Wrap(AnsiString)
  near: const param  Wrap  a  >>>  <hi>  
pascal26:111: error: no overload of ChkS matches these arguments
  argument types: (ShortString, Integer, ShortString)
  candidates:
    ChkS(AnsiString, AnsiString, AnsiString)
  near:  a   <hi>  >>>  Chk  
pascal26:112: error: no overload of WrapV matches these arguments
  argument types: (Char)
  candidates:
    WrapV(AnsiString)
  near: value param  WrapV  a  >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
