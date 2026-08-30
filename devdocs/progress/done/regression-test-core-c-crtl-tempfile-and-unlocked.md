---
prio: 70
track: C
---

> **Track guessed as C** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 16 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/c_crtl_tempfile_and_unlocked.c red at 7227f3e0f1f8 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T19:49:31Z
- **Test source:** test/c_crtl_tempfile_and_unlocked.c tools/expect_same.sh

## Repro
`tools/testmgr.py --tier full --job 'test-core#src:test/c_crtl_tempfile_and_unlocked.c'` at 7227f3e0f1f8343547d85f7fc3a32c2f440686dd

## Range
> **The named sha `7227f3e0f1f8` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `7227f3e0f1f8`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
ok: /tmp/testmgr-scratch-1722017/c_crtl_tmp26  [code=241432B  data=11368B  bss=63584B  procs=677]
expect_same: MISMATCH [c_crtl_tmp26]
--- expected
+++ actual
@@ -14,5 +14,5 @@
 fwrite_unlocked ok
 ftrylockfile: 0
 fchdir: 0
-fchdir landed /tmp/testmgr-scratch-1722017: 1
+fchdir landed /tmp: 1
 ttyname_r(0) rc class: 1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-30 — auto-closed by the seven watcher: `test-core#src:test/c_crtl_tempfile_and_unlocked.c` passes at dbab98d339c7 (tier native); it was red at 7227f3e0f1f8. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
