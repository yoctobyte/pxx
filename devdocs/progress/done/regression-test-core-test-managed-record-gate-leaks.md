---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 3 of 3 is `tools/assert_no_leak.sh managed_record_gate 50 /tmp/test_mrg26`. The job's own `src` (`test/test_managed_record_gate_leaks.pas`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_managed_record_gate_leaks`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `assert_no_leak`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_managed_record_gate_leaks.pas at 4fbed6c4157e in step 3/3, `tools/assert_no_leak.sh managed_record_gate 50 /tmp/test_mrg26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-18T10:37:47Z
- **Test source:** test/test_managed_record_gate_leaks.pas tools/expect_same.sh +1
- **Failing step:** line 3 of 3 of the job's recipe; it names `tools/assert_no_leak.sh`.
  ```
  tools/assert_no_leak.sh managed_record_gate 50 /tmp/test_mrg26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_managed_record_gate_leaks.pas'` at 4fbed6c4157ef53972bae9ffb923ecf029f50725

## Range
> **The named sha `4fbed6c4157e` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `4fbed6c4157e`, last good `7f86a12a6628`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
:12770 48:15618 56:4807 64:1272 72:20 88:2235 152:637 280:637
pxx-census: allocs=64239 frees=62800 live=1439 bytes=3032712 reuse=62788 list=0 bump=1451 arenas=1
pxx-census: sizes 32:21497 40:14363 48:17575 56:5404 64:1432 72:20 88:2514 152:717 280:717
pxx-census: allocs=72269 frees=70655 live=1614 bytes=3411816 reuse=70638 list=0 bump=1631 arenas=1
pxx-census: sizes 32:24189 40:16155 48:19773 56:6078 64:1612 72:20 88:2828 152:807 280:807
pxx-census: allocs=81303 frees=79482 live=1821 bytes=3837848 reuse=79471 list=0 bump=1832 arenas=1
pxx-census: sizes 32:27213 40:18179 48:22249 56:6835 64:1812 72:20 88:3181 152:907 280:907
pxx-census: allocs=91466 frees=89418 live=2048 bytes=4317624 reuse=89407 list=0 bump=2059 arenas=1
pxx-census: sizes 32:30625 40:20447 48:25026 56:7687 64:2040 72:20 88:3579 152:1021 280:1021
pxx-census: allocs=102900 frees=100597 live=2303 bytes=4857336 reuse=100585 list=0 bump=2315 arenas=1
pxx-census: sizes 32:34457 40:23003 48:28156 56:8644 64:2296 72:20 88:4026 152:1149 280:1149
pxx-census: allocs=115763 frees=113177 live=2586 bytes=5464160 reuse=113160 list=0 bump=2603 arenas=1
pxx-census: sizes 32:38769 40:25875 48:31680 56:9723 64:2584 72:20 88:4528 152:1292 280:1292
pxx-census: allocs=130234 frees=127320 live=2914 bytes=6147208 reuse=127308 list=0 bump=2926 arenas=1
pxx-census: sizes 32:43622 40:29107 48:35640 56:10936 64:2907 72:20 88:5094 152:1454 280:1454
pxx-census: allocs=146514 frees=143236 live=3278 bytes=6915592 reuse=143224 list=0 bump=3290 arenas=1
pxx-census: sizes 32:49076 40:32747 48:40098 56:12300 64:3271 72:20 88:5730 152:1636 280:1636
pxx-census: allocs=164829 frees=161142 live=3687 bytes=7780120 reuse=161130 list=0 bump=3699 arenas=1
pxx-census: sizes 32:55217 40:36841 48:45107 56:13834 64:3680 72:20 88:6448 152:1841 280:1841
assert_no_leak[managed_record_gate]: LEAK — live=3687 exceeds 50
  allocs=164829 frees=161142
  pxx-census: allocs=164829 frees=161142 live=3687 bytes=7780120 reuse=161130 list=0 bump=3699 arenas=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-18 — auto-closed by the borg watcher: `test-core#src:test/test_managed_record_gate_leaks.pas` passes at 2b8480963d5f (tier native); it was red at 4fbed6c4157e. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
