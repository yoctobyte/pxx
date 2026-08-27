---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_pascal_cast_chain_method_call.pas red at 97f96a5cc766 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-27T03:27:54Z
- **Test source:** test/test_pascal_cast_chain_method_call.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_pascal_cast_chain_method_call.pas'` at 97f96a5cc7664fb2521b3fa5d0bd5de681b6c0d2

## Range
> **The named sha `97f96a5cc766` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `97f96a5cc766`, last good `67a83ca0bb63`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:100: error: "NewN": this value has no members (only records, classes, interfaces and variants do)
pascal26:100: error: expected comma or close parenthesis
(tail)
pascal26:100: error: "NewN": this value has no members (only records, classes, interfaces and variants do)
  near: q    cr  >>> NewN   
pascal26:100: error: expected comma or close parenthesis
  near:    cr  NewN >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
