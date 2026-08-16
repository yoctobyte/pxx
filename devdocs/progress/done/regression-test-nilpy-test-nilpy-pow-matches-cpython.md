---
prio: 70
track: N
status: done
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_pow_matches_cpython.npy red at 096da361dd93 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-16T11:09:21Z
- **Test source:** test/test_nilpy_pow_matches_cpython.npy test/test_nilpy_pow_matches_cpython.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_pow_matches_cpython.npy'` at 096da361dd93823dc6aa56f7a344de5f343127ec

## Range
bad `096da361dd93`, last good `459e96f985d1`, 32 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1820057/test_nilpy_pow26  [code=2429383B  data=48620B  bss=10012B  procs=1926]
--- test/test_nilpy_pow_matches_cpython.expected	2026-08-16 01:45:04.069549215 +0200
+++ -	2026-08-16 12:55:50.300756373 +0200
@@ -4,7 +4,7 @@
 2.7181459268249255
 2.7181459268249255
 2.7181459268249255
-ValueError
+(-0+2.8284271247461894j)
 ZeroDivisionError
 1024 1 -8 0.5
 0.125 1e+100 2.25 0.007713560673657699

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Verified GREEN 2026-08-16 by Track T — and the bisect was RIGHT but not a culprit

```
tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_pow_matches_cpython.npy'
  testmgr: GREEN
```

at HEAD with the compiler rebuilt, after `87c1cd7c1`.

**The bisect named `ba5a9d9878fa` ("feat(N): Python's complex type") and that is
the commit that changed the answer — but it is a feature, not a fault.** The
`.expected` asserted `ValueError` for `(-8.0) ** 0.5`, a *deliberate* divergence
recorded when NilPy had no complex type. The feature retired the divergence and
left the expectation behind.

Worth recording as a third bisect category, alongside the two this week:

| bisect result | what it means |
| --- | --- |
| a real first-failure | the ordinary case — fix the commit |
| an innocent commit | the signal was a TIMEOUT, not behaviour ([[bug-t-a-timeout-bisects-to-an-innocent-commit]]) |
| **a correct commit that is not a fault** | a feature retired a recorded divergence and the expectation was left behind — **this one** |

The third is the one a stub cannot distinguish, because the bisect is *right*:
the range converges honestly on the commit that changed the behaviour. Only a
human reading the `.expected` can tell "the answer changed because we fixed
something" from "the answer changed because we broke something". Nothing to fix
in the tool here — recorded so the next reader does not treat a converged range
as an accusation.

**Pin note:** the fix is in `compiler/builtin/pylib.pas`, so anything built with
the PINNED binary keeps the old `-0` real part until the next pin. This test
builds with `$(COMPILER)`, which is why it is green now. No re-pin was taken for
it; it should ride whatever pin comes next.
- 2026-08-16 — resolved, commit cabd1508c.
