---
prio: 70
status: done
owner: claude-A
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-i386#src:test/test_dynarray_field.pas red at 899e51cda3ba (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-06T19:03:41Z
- **Test source:** test/test_dynarray_field.pas tools/run_target.sh

## Repro
`tools/testmgr.py --tier full --job 'test-i386#src:test/test_dynarray_field.pas'` at 899e51cda3ba24d5faa2e5e6d4c3985e3cdc53d1

## Range
bad `899e51cda3ba`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2456798/test_i386_dynfield  [code=67861B  data=2560B  bss=9504B  procs=100]
ok: /tmp/testmgr-scratch-2456798/test_i386_dynfield_x64  [code=50227B  data=2472B  bss=9548B  procs=100]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## RESOLVED 2026-08-08 — already fixed; verified, not assumed

Green at current HEAD, and not a flake: `tools/testmgr.py --tier full --job
'test-i386#src:test/test_dynarray_field.pas'` run four times, GREEN every time.

Fixed by **baa606d36** *"fix(A): i386 also COW'd nested dyn-arrays; retire the
nested-COW test"* (2026-08-06 22:44), which lands 1h53m after the bad sha this
stub was filed against (899e51cda, 2026-08-06 20:51). Its sibling 937c51dc2
*"dynamic arrays ALIAS on assignment, like FPC — the COW is gone"* is the
substantive change; the i386 backend needed the same treatment and got it there.

The current `tstate/plexus.json` agrees — `test_dynarray_field.pas` reads `pass`
on every target that runs it (i386, aarch64, arm32, riscv32, core), so nothing
is being held open for it.

No code change needed. Closed as an already-fixed watcher stub rather than
rejected: the regression was real when filed.
- 2026-08-08 — resolved, commit ed6e77bbf.
