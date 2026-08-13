---
prio: 70
status: done
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_uses_order_pylib_exception_a.pas red at 1df75aad5458 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-13T19:31:25Z
- **Test source:** test/test_uses_order_pylib_exception_a.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_uses_order_pylib_exception_a.pas'` at 1df75aad5458bf3ab272964dea010a8ff15f26c0

## Range
bad `1df75aad5458`, last good `432867370a9e`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:4806: error: "argsv": no such member on this record/class
(tail)
pascal26:4806: error: "argsv": no such member on this record/class
  near: k    e  >>> argsv  TPyList 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## TRIAGED 2026-08-13 by Track T — consolidated into the Track A ticket

Reproduced at HEAD with a freshly rebuilt compiler:
`pascal26:4824: error: "argsv": no such member on this record/class`.

Not a new bug. This is [[bug-pascal-uses-order-breaks-pylib-exception]]
returning — that ticket's own two-line repro fails again, with a different
field. **Reopened at prio 70 and moved back to backlog**; everything is
recorded there.

Attribution, so nobody re-derives it: the range holds one semantic commit,
`67910b097 feat(N): e.args, and the KeyError repr it unblocked`, which added the
`argsv` field to pylib's `Exception`. That is the TRIGGER, not the cause —
adding a field to your own unit's class is ordinary code, and reverting it would
only re-arm the trap for the next field. Do not route this to Track N.
- 2026-08-13 — resolved, commit PENDING-COMMIT.
