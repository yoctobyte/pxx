---
prio: 70
status: done
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_cpyext_markupsafe.npy red at 34c41bde6fd6 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-05T19:36:23Z
- **Test source:** test/test_cpyext_markupsafe.npy test/nilpy_units/vendor/cyadd.pyx

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_cpyext_markupsafe.npy'` at 34c41bde6fd66529206b2891337066a5a9fae50c

## Range
bad `34c41bde6fd6`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:15: error: uses: unit source not found: /lib/cpyext/src/pyruntime.c
(tail)
pascal26:15: error: uses: unit source not found: /lib/cpyext/src/pyruntime.c
  near:  interface uses pxxcio  ../../lib/cpyext/src/pyruntime.c >>>  ./vendor/_speedups.c  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-08-06 — STALE STUB, closing: the watcher itself already reported it FIXED

Not a live red. This is one of the batch that went red together at
`34c41bde6fd6` on 2026-08-05 and that the watcher's own next reports moved to
**FIXED** within the hour —
`tstate/reports/20260805T194256Z-8b9d08b-plexus.md` and
`tstate/reports/20260805T203501Z-aba953c-plexus.md`. The auto-filed stub was
never closed, so it kept sitting near the head of the ranked queue.

Re-verified at HEAD `733be3321` (compiler snapshot sha256 `cafd50517875`) by
running the stub's own repro line: PASS.

**No code change.** A whole family of tests sharing one `uses` line going red and
green together points at the transient tree state at `34c41bde6fd6`, not at any
one of these tests. The process lesson is the one CLAUDE.md already states: an
async watcher callback is tagged to the sha it was tested at and must be
re-checked against current HEAD before acting.

Track T follow-up filed separately: the watcher does not close or annotate a
NEW-RED stub when a later report moves the same job to FIXED, so a self-healing
red leaves a permanent prio-70 item at the head of the queue.
- 2026-08-06 — resolved, commit f66c75e75.
