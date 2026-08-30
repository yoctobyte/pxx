---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 14 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_sched_reactor_exhaustion.pas red at 2b33ab009963 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-29T19:36:31Z
- **Test source:** test/test_sched_reactor_exhaustion.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_sched_reactor_exhaustion.pas'` at 2b33ab009963d41b65dbb92d441ed857ea36a2a8

## Range
> **The named sha `2b33ab009963` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `2b33ab009963`, last good `c513c0190421`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
-fatal: scheduler out of reactor slots (MAX_REACTORS)
(tail)
ok: /tmp/testmgr-scratch-995829/test_sched_exhaust26  [code=130464B  data=3976B  bss=47348B  procs=298]
expect_same: MISMATCH [test_sched_exhaust26-msg]
--- expected
+++ actual
@@ -1 +1 @@
-fatal: scheduler out of reactor slots (MAX_REACTORS)
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-29 — auto-closed by the plexus watcher: `test-threads#src:test/test_sched_reactor_exhaustion.pas` passes at 4614092ab517 (tier native); it was red at 2b33ab009963. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
