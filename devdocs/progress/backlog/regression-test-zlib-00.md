---
prio: 70
---

# regression: test-zlib#00 red at 83006e927e35 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-12T04:27:56Z
- **Test source:** tools/install_lib_candidates.sh test/example.c +1

## Repro
`tools/testmgr.py --tier full --job 'test-zlib#00'` at 83006e927e35b02e76728c3a292e08dbcc0b792e

## Range
bad `83006e927e35`, last good `83006e927e35`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
building gcc oracle ...
compiling pxx zlib runner ...
pascal26:1891: error: call to undeclared function: copysign ()

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
