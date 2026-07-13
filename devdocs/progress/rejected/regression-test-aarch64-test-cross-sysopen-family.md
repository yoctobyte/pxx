---
prio: 70
---

# regression: test-aarch64#src:test/test_cross_sysopen_family.pas red at a5fc06ee29b6 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-13T05:54:30Z
- **Test source:** test/test_cross_sysopen_family.pas tools/run_target.sh

## Repro
`tools/testmgr.py --tier full --job 'test-aarch64#src:test/test_cross_sysopen_family.pas'` at a5fc06ee29b63a859c5a8f0ac17ad2e8435c7144

## Range
bad `a5fc06ee29b6`, last good `a5fc06ee29b6`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3463314/test_aarch64_sysopen_family  [code=74812B  data=176B  bss=9468B  procs=65]
ok: /tmp/testmgr-scratch-3463314/test_aarch64_sysopen_family_x64  [code=32928B  data=224B  bss=9468B  procs=65]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triage 2026-07-13 (Track A) — NOT A REGRESSION, transient

Green at HEAD: `tools/testmgr.py --tier full --job 'test-aarch64#src:test/test_cross_sysopen_family.pas'`
→ `1/1 pass`. The watcher itself already recorded it as FIXED one SHA later
(`tstate/reports/20260713T060754Z-9b93d1c-borg.md`, verdict GREEN) with no
intervening change to the aarch64 backend or to that test.

Three things say "harness", not "codegen":
- the range is `bad a5fc06ee`, `last good a5fc06ee` — **0 commits**, i.e. the same
  commit was both good and bad;
- the log tail ends with BOTH binaries emitted `ok:` and then nothing — no wrong
  output, no diff, no non-zero exit line. A miscompile fails loudly at the compare;
  a killed/timed-out qemu run fails exactly like this;
- `a5fc06ee` (advanced-record constructors) is a frontend commit that cannot reach
  the aarch64 backend.

Same shape as the earlier cjson/lua borg reds that turned out to be a scratch-dir
race, so the suspicion is the run side (qemu launch under the memory scope), not the
emitted code. Closing as rejected rather than done: nothing was fixed. If it comes
back, instrument the harness (capture qemu's exit status and stderr into the log tail)
before suspecting the backend — the current log tail cannot distinguish "ran and printed
the wrong thing" from "never ran".
