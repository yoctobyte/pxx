---
prio: 70
---


> **Root cause already diagnosed — see [[bug-c-plain-char-lost-its-type-identity-not-just-its-signedness]].**
> One commit (`07414aa89`) turned plain `char` into an 8-bit integer
> rather than a signed character type. Do not triage this stub
> separately; it goes green when that ticket does.
> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/cgeneric_selection_b209.c red at 42786f141ea7 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-03T10:55:23Z
- **Test source:** test/cgeneric_selection_b209.c

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/cgeneric_selection_b209.c'` at 42786f141ea7b8b86f84b8f074d887f0e98c1401

## Range
bad `42786f141ea7`, last good `2028afba02ca`, 3 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:35: error: _Generic: no matching association and no default
  near:       >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
