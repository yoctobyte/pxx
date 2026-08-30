---
prio: 70
track: T
---

> **Track T by default, because this job TIMED OUT.** The source path says what a job compiles, not what went wrong, and a timeout did not fail in any of its sources — it ran out of budget. Guessing a lane from the path is the wrong turn `bug-t-a-timeout-bisects-to-an-innocent-commit` was filed to stop, so a timeout stays T's until someone shows otherwise. Re-lane it if the budget was not the problem.

> **origin/master has advanced 10 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_static_string_literals.pas@2 red at 5bb3e120d3f7 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-30T04:25:16Z
- **Test source:** test/test_static_string_literals.pas tools/expect_same.sh +1

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_static_string_literals.pas@2'` at 5bb3e120d3f7e9f32452b1bf462f9f07fc7f5832

## Range
> **The named sha `5bb3e120d3f7` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `5bb3e120d3f7`, last good `0c99981669b7`, 8 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-307305/test_ssl026  [code=87344B  data=3680B  bss=42524B  procs=132]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-30 — auto-closed by the plexus watcher: `test-threads#src:test/test_static_string_literals.pas@2` passes at 0f0a5619a413 (tier native); it was red at 5bb3e120d3f7. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
