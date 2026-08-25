---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_arr_of_ptr_elemrec_b354.pas red at 10dada0b7689 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-25T16:38:27Z
- **Test source:** test/test_arr_of_ptr_elemrec_b354.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_arr_of_ptr_elemrec_b354.pas'` at 10dada0b7689fee546516eec7ea90d1da4256053

## Range
bad `10dada0b7689`, last good `d20300d288eb`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:51: error: "A": this value has no members (only records, classes, interfaces and variants do)
pascal26:51: error: "B": this value has no members (only records, classes, interfaces and variants do)
pascal26:51: error: "C": this value has no members (only records, classes, interfaces and variants do)
(tail)
pascal26:51: error: "A": this value has no members (only records, classes, interfaces and variants do)
  near: lst  i    >>> A    
pascal26:51: error: "B": this value has no members (only records, classes, interfaces and variants do)
  near: lst  i    >>> B    
pascal26:51: error: "C": this value has no members (only records, classes, interfaces and variants do)
  near: lst  i    >>> C   

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
