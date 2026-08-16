---
prio: 70
track: T
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/crtl_exp2.c red at 096da361dd93 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-16T11:09:21Z
- **Test source:** test/crtl_exp2.c examples/tk/hello.npy +5

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/crtl_exp2.c'` at 096da361dd93823dc6aa56f7a344de5f343127ec

## Range
bad `096da361dd93`, last good `459e96f985d1`, 32 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1820057/crtl_exp2  [code=228732B  data=5400B  bss=23080B  procs=582]
  tk-nilpy: ok

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triaged 2026-08-16 by Track T — a TIMEOUT, not a C regression

Do not read the job name as the culprit. This job's sources are
`test/crtl_exp2.c examples/tk/hello.npy +5`, and the key names only the FIRST of
them; the capture cuts right after `tk-nilpy: ok`, i.e. in a different source.
Every step runs clean standalone in seconds, and `lib-test` passes **167/167**
when given the box.

It is the job exceeding its total budget under a 2500-job full tier, not a
failure. `wall` sat at 1133-1145s across six consecutive full runs at six
different shas — the shape of a cap being hit, not of a defect reproducing.

**Kept in Track T deliberately.** The obvious guess from the source path is C,
and that guess is wrong here: nothing in C is broken, and sending it to C is the
exact wrong turn [[bug-t-a-timeout-bisects-to-an-innocent-commit]] was filed to
prevent. The remedy is T's — make the job cheaper, or make its budget honest.

Related: [[chore-t-split-lib-test-into-jobs-that-name-what-failed]] (so the key
names the step that actually failed), and the parent ticket, which stopped the
bisect from naming an innocent commit.

## Log
- 2026-08-16 — auto-closed by the plexus watcher: `lib-test#src:test/crtl_exp2.c` passes at d91b82d6516b (tier full); it was red at 096da361dd93. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
