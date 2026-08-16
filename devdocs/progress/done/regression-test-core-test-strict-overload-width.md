---
prio: 70
track: P
type: regression
summary: "RESOLVED — not a defect. An intended EXPECTATION change: Integer and LongInt are one 4-byte signed type, so the LongInt overload is an exact match and the exact phase now sees it. Fixed forward in 58f5ef974; auto-closed by the watcher and independently verified GREEN at HEAD by Track T."
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_strict_overload_width.pas@1 red at fea1f33d2f30 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-16T07:00:28Z
- **Test source:** test/test_strict_overload_width.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_strict_overload_width.pas@1'` at fea1f33d2f304d829a0422bc36f938edc411bc57

## Range
bad `fea1f33d2f30`, last good `8938aed7d55b`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1184201/test_sow_default26  [code=236664B  data=9140B  bss=42784B  procs=561]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-16 — auto-closed by the plexus watcher: `test-core#src:test/test_strict_overload_width.pas@1` passes at c1b4fa782263 (tier native); it was red at fea1f33d2f30. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.

## Triage 2026-08-16 by Track T (face 2) — kept, though the watcher auto-closed it

The watcher's `--recheck` closed this on its own when the job went green, which
is the mechanism working. Recording the *reason* anyway, because the auto-close
proves the red went away and says nothing about what it was.

Not a defect and not a flake: an intended **expectation** change, fixed forward
in `58f5ef974`. Independently re-verified with the compiler rebuilt at HEAD —
`test-core#729 PASS`, `testmgr: GREEN`.

### What moved, and why it is NOT the flag leaking

"A `--strict-overload-width` test changed in its DEFAULT column" has one obvious
reading, and that reading is wrong.

Four rows of the default column moved (`Integer`, `literal`, `MyInt` ->
`longint`, `hex` -> `FFFFFFFF`). The `--strict-overload-width` column did not
move at all.

Nothing is being *ranked*. `Integer` and `LongInt` are one 4-byte signed type —
FPC declares one as the other's alias — so the LongInt overload is an **exact**
match, and the exact phase now sees it. The user's 2026-08-14 decision was about
ranking between DIFFERENT widths, which the default still declines to do:
`SmallInt`, `Byte` and `Cardinal` still widen to `Int64` unflagged. All four
rows that moved moved toward FPC, which is the standing default.

### Filing note — second time today

The stub carried only `prio:` in frontmatter, so it ranked in **Track T's**
queue with its subject matter in prose — the same shape as
`meta-track-w-collision-windows-vs-website`, and the same thing that happened to
`regression-lib-test-crtl-reachability` hours earlier. `track:` and `summary:`
added here. Worth twatch guessing a `track:` from the test path when it files a
stub, rather than each triager fixing it by hand.
