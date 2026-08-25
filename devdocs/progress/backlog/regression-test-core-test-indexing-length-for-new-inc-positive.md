---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_indexing_length_for_new_inc_positive.pas red at ae6251f917bb (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-25T17:42:09Z
- **Test source:** test/test_indexing_length_for_new_inc_positive.pas test/test_indexing_length_for_new_inc_positive.expected +1

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_indexing_length_for_new_inc_positive.pas'` at ae6251f917bb06e80679e1da8253957106b1fd13

## Range
bad `ae6251f917bb`, last good `10dada0b7689`, 8 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:44: error: illegal counter variable: a counted for needs an ordinal (integer, char, boolean, enum or subrange) (s)
pascal26:45: error: this value cannot be indexed — only arrays, strings and pointers can (i)
pascal26:46: error: New needs a pointer variable, not Integer (i)
pascal26:47: error: Inc/Dec needs an ordinal or a pointer, not AnsiString
pascal26:48: error: Length needs a string, an array or a PChar, not Integer
pascal26:50: error: with needs a record, class or interface — Integer has no members
pascal26:51: error: cannot assign to the result of a function call
(tail)
ok: /tmp/testmgr-scratch-1996518/test_ilfni26  [code=235935B  data=5200B  bss=43132B  procs=636]
test_scalar_misuse_is_refused_fail: FAIL - rc=1 (want rc=1, eight diagnostics on lines 44-51, no binary)
pascal26:44: error: illegal counter variable: a counted for needs an ordinal (integer, char, boolean, enum or subrange) (s)
  near: i    for s >>>   to 
pascal26:45: error: this value cannot be indexed — only arrays, strings and pointers can (i)
  near: j  i    >>>  New  
pascal26:46: error: New needs a pointer variable, not Integer (i)
  near:   New  i  >>>  Inc  
pascal26:47: error: Inc/Dec needs an ordinal or a pointer, not AnsiString
  near:   Inc  s  >>>  j  
pascal26:48: error: Length needs a string, an array or a PChar, not Integer
  near: j  Length  i  >>>  b  
pascal26:50: error: with needs a record, class or interface — Integer has no members
  near: r    with i >>> do WriteLn  
pascal26:51: error: cannot assign to the result of a function call
  near:   F1    >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
