---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_length_dynarray_call.pas red at b936d125601e (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-25T06:10:55Z
- **Test source:** test/test_length_dynarray_call.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_length_dynarray_call.pas'` at b936d125601ea26a9e570d65be152ff3a35d04a0

## Range
bad `b936d125601e`, last good `0626344011cf`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:29: error: Length needs a string, an array or a PChar, not Pointer
pascal26:30: error: Length needs a string, an array or a PChar, not Pointer
pascal26:31: error: Length needs a string, an array or a PChar, not Pointer
pascal26:32: error: Length needs a string, an array or a PChar, not Pointer
pascal26:33: error: Length needs a string, an array or a PChar, not Pointer
(tail)
pascal26:29: error: Length needs a string, an array or a PChar, not Pointer
  near:  MakeArr     >>>   writeln 
pascal26:30: error: Length needs a string, an array or a PChar, not Pointer
  near:  MakeArr     >>>   writeln 
pascal26:31: error: Length needs a string, an array or a PChar, not Pointer
  near: writeln  Length  MakeEmpty  >>>   writeln 
pascal26:32: error: Length needs a string, an array or a PChar, not Pointer
  near:  MakeStrs     >>>   writeln 
pascal26:33: error: Length needs a string, an array or a PChar, not Pointer
  near:  MakeStrs     >>>   end 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
