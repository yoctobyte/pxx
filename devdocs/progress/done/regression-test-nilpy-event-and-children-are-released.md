---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `if command -v xvfb-run >/dev/null 2>&1; then \ tools/expect_same.sh nilpy_tk_event_children_value "$(timeout 120 env GDK`. The job's own `src` (`examples/tk/event_and_children_are_released.npy`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `event_and_children_are_released`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# first-ever red: test-nilpy#src:examples/tk/event_and_children_are_released.npy at fc6f76591258 in step 2/2, `if command -v xvfb-run >/dev/null 2>&1; then \ tools/expect_same.sh nilpy_tk_event_children_value "$(timeout 120 env GD…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-29T03:01:21Z
- **Test source:** examples/tk/event_and_children_are_released.npy tools/expect_same.sh +1
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh tools/assert_no_leak.sh`.
  ```
  if command -v xvfb-run >/dev/null 2>&1; then \ tools/expect_same.sh nilpy_tk_event_children_value "$(timeout 120 env GDK_BACKEND=x11 xvfb-run -a /tmp/test_nilpy_tkevrel26 2>/dev/null)" "True 900 2" || exit 1; \ tools/assert_no_leak.sh nilpy_tk_event_children_released 100 timeout 120 env GDK_BACKEND=
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:examples/tk/event_and_children_are_released.npy'` at fc6f765912586216a49a40da8ef8dc371f4e5be0

## Range
> **The named sha `fc6f76591258` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `fc6f76591258`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
8:65
+pxx-census: allocs=2369 frees=2345 live=24 bytes=103712 reuse=2327 list=0 bump=42 arenas=1
+pxx-census: sizes 32:1099 40:373 48:388 56:360 64:1 72:71 80:4 128:73
+pxx-census: allocs=2666 frees=2641 live=25 bytes=116680 reuse=2624 list=0 bump=42 arenas=1
+pxx-census: sizes 32:1239 40:420 48:433 56:406 64:1 72:81 80:4 128:82
+pxx-census: allocs=3000 frees=2970 live=30 bytes=131360 reuse=2958 list=0 bump=42 arenas=1
+pxx-census: sizes 32:1395 40:470 48:487 56:459 64:1 72:91 80:4 128:93
+pxx-census: allocs=3376 frees=3353 live=23 bytes=147672 reuse=3334 list=0 bump=42 arenas=1
+pxx-census: sizes 32:1575 40:530 48:543 56:516 64:1 72:103 80:4 128:104
+pxx-census: allocs=3799 frees=3770 live=29 bytes=166312 reuse=3757 list=0 bump=42 arenas=1
+pxx-census: sizes 32:1770 40:595 48:611 56:584 64:1 72:116 80:4 128:118
+pxx-census: allocs=4274 frees=4250 live=24 bytes=186976 reuse=4232 list=0 bump=42 arenas=1
+pxx-census: sizes 32:1995 40:670 48:684 56:657 64:1 72:131 80:4 128:132
+pxx-census: allocs=4809 frees=4784 live=25 bytes=210448 reuse=4767 list=0 bump=42 arenas=1
+pxx-census: sizes 32:2243 40:755 48:768 56:741 64:1 72:148 80:4 128:149
+pxx-census: allocs=5411 frees=5387 live=24 bytes=236792 reuse=5369 list=0 bump=42 arenas=1
+pxx-census: sizes 32:2524 40:850 48:863 56:835 64:1 72:166 80:4 128:168
+pxx-census: allocs=6088 frees=6063 live=25 bytes=266416 reuse=6046 list=0 bump=42 arenas=1
+pxx-census: sizes 32:2842 40:955 48:968 56:941 64:1 72:188 80:4 128:189
+pxx-census: allocs=6850 frees=6826 live=24 bytes=299752 reuse=6808 list=0 bump=42 arenas=1
+pxx-census: sizes 32:3199 40:1074 48:1088 56:1060 64:1 72:211 80:4 128:213
+pxx-census: allocs=7707 frees=7684 live=23 bytes=337296 reuse=7665 list=0 bump=42 arenas=1
+pxx-census: sizes 32:3601 40:1205 48:1223 56:1195 64:1 72:238 80:4 128:240
+pxx-census: allocs=8671 frees=8646 live=25 bytes=379432 reuse=8629 list=0 bump=42 arenas=1
+pxx-census: sizes 32:4054 40:1356 48:1373 56:1345 64:1 72:268 80:4 128:270
 True 900 2

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-29 — auto-closed by the borg watcher: `test-nilpy#src:examples/tk/event_and_children_are_released.npy` passes at 1086f130add0 (tier full); it was red at fc6f76591258. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
