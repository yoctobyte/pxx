---
prio: 70
status: done
owner: claude-AN
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_forward_module_global.npy red at dbf783346025 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-15T04:12:43Z
- **Test source:** test/test_nilpy_forward_module_global.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_forward_module_global.npy'` at dbf783346025ce00ed6885ae6a6b8d3afb4692b9

## Range
bad `dbf783346025`, last good `17c01ba0a0a0`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1806961/test_nilpy_fwdglob26  [code=2152178B  data=44616B  bss=8548B  procs=1603]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triage + fix (2026-08-15, Track N)

Mine, from `9496262c9` (a nested def shadows a module global of the same name)
— the watcher's range was right.

`n=7` came out as `n=4727019`: a code ADDRESS. The module global `counter` was
being read as a function VALUE.

`PyNestedDefOutranksSym` asked `FindProc(PyQualifyNested(name)) >= 0`, and
**`PyQualifyNested` answers the BARE name when nothing qualified exists** — so
the test degenerated to "is there ANY proc of this name?". Proc lookup is
case-INSENSITIVE (Pascal heritage), so `counter` matched pylib's `Counter`,
the helper said the global was outranked, and the callable-value arm claimed
every read of it.

The helper's question is only ever "does a NESTED def outrank the global", so
it now requires the qualification to have actually happened
(`PyQualifyNested(name) <> name`) before asking FindProc. The two tests that
motivated the original change — `nested_def_outer_name_collision`,
`nested_def_default_at_def_time` — still pass.

Worth keeping: the failure was invisible unless the global's name collided
case-insensitively with a builtin. A gate at HEAD would not have caught it;
the corpus test did.

The underlying collision — a Python name being resolved case-insensitively
against builtins, where Python is case-sensitive — is filed separately as
[[bug-nilpy-a-global-collides-case-insensitively-with-a-builtin-proc]].

### Gate

`make compiler/pascal26` + `tools/gate.sh quick` GREEN;
`test/test_nilpy_forward_module_global.npy` matches CPython again.
- 2026-08-15 — resolved, commit PENDING-COMMIT.
