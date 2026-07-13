---
prio: 70
---

# regression: test-core#src:test/test_string_to_pchar_auto.pas red at 8997639f144f (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-13T01:51:35Z
- **Test source:** test/test_string_to_pchar_auto.pas

## Repro
`tools/testmgr.py --tier full --job 'test-core#src:test/test_string_to_pchar_auto.pas'` at 8997639f144fc690145e51c980d5c50b94986a89

## Range
bad `8997639f144f`, last good `8997639f144f`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2417024/string_to_pchar_auto26  [code=48921B  data=1488B  bss=9520B  procs=578]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
