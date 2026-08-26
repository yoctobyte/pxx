---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/dev has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_type_name_of_a_big_int.npy red at 44193e547f6d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-25T20:32:52Z
- **Test source:** test/test_nilpy_type_name_of_a_big_int.npy test/test_nilpy_type_name_of_a_big_int.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_type_name_of_a_big_int.npy'` at 44193e547f6d4ca77453770378b710d8af82f5df

## Range
bad `44193e547f6d`, last good `d2cb6721e175`, 23 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2553870/test_nilpy_typebig26  [code=2317884B  data=55230B  bss=43340B  procs=1988]
--- test/test_nilpy_type_name_of_a_big_int.expected	2026-08-13 07:02:31.902669004 +0200
+++ -	2026-08-25 22:03:53.631275002 +0200
@@ -4,5 +4,5 @@
 int float str bool
 list dict tuple NoneType
 K type
-function
+method
 1180591620717411303424 1180591620717411303424 1180591620717411303424 1180591620717411303424 1180591620717411303424

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## CORRECTION — the range above is WRONG, and too narrow (Track T, 2026-08-25)

**Do not bisect the 23-commit range this ticket was filed with.** The job named
here does not run in the `native` tier, and the parent it was diffed against
(`d2cb6721e175`) was a native run. It last actually executed in the full tier at
`aa9f0989a4c0` on 2026-08-24 — so the honest range is **179 commits**
(`aa9f0989a4c0..44193e547f6d`), not 23, and the last-good sha is
`aa9f0989a4c0`, not `d2cb6721e175`.

This matters more than the arithmetic suggests. A bisect over a range that does
not contain the culprit does not fail and does not report "not found" — it
narrows, confidently, onto an innocent commit, and a core-job red is a revert
candidate by this repo's own rule. The 23-commit window is precisely the set of
commits that CANNOT have caused this, since the job was already in this state
before the window opened.

Cause: `twatch` computed the blame range from "since this host last tested
anything" rather than "since this job last ran". Fixed in `c68e6492e` —
the range is now decided per job from `job_tier` and widened only when the
parent's run provably did not contain it. Tickets filed from later runs carry
the corrected range; this one is annotated rather than rewritten, because the
filed text is the record of what the watcher actually claimed.
