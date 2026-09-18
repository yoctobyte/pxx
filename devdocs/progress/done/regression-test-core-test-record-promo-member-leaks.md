---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 3 of 21 is `tools/assert_no_leak.sh record_promo_member 50 /tmp/test_rpm26`. The job's own `src` (`test/test_record_promo_member_leaks.pas`, 5 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_record_promo_member_leaks`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `assert_no_leak`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_record_promo_member_leaks.pas at 4fbed6c4157e in step 3/21, `tools/assert_no_leak.sh record_promo_member 50 /tmp/test_rpm26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-18T10:37:47Z
- **Test source:** test/test_record_promo_member_leaks.pas tools/expect_same.sh +3
- **Failing step:** line 3 of 21 of the job's recipe; it names `tools/assert_no_leak.sh`.
  ```
  tools/assert_no_leak.sh record_promo_member 50 /tmp/test_rpm26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_record_promo_member_leaks.pas'` at 4fbed6c4157ef53972bae9ffb923ecf029f50725

## Range
> **The named sha `4fbed6c4157e` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `4fbed6c4157e`, last good `7f86a12a6628`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
 live=2878 bytes=5301504 reuse=112870 list=0 bump=2893 arenas=1
pxx-census: sizes 32:34125 40:28763 48:33423 56:10807 64:2513 72:1457 88:3597 120:360 216:359 408:359
pxx-census: allocs=130234 frees=126995 live=3239 bytes=5964048 reuse=126981 list=0 bump=3253 arenas=1
pxx-census: sizes 32:38397 40:32361 48:37599 56:12154 64:2828 72:1636 88:4046 120:405 216:404 408:404
pxx-census: allocs=146514 frees=142869 live=3645 bytes=6709248 reuse=142858 list=0 bump=3656 arenas=1
pxx-census: sizes 32:43194 40:36410 48:42303 56:13672 64:3181 72:1839 88:4552 120:455 216:454 408:454
pxx-census: allocs=164829 frees=160730 live=4099 bytes=7547984 reuse=160718 list=0 bump=4111 arenas=1
pxx-census: sizes 32:48599 40:40955 48:47595 56:15379 64:3579 72:2067 88:5121 120:512 216:511 408:511
pxx-census: allocs=185433 frees=180823 live=4610 bytes=8491472 reuse=180810 list=0 bump=4623 arenas=1
pxx-census: sizes 32:54675 40:46075 48:53547 56:17299 64:4027 72:2323 88:5761 120:576 216:575 408:575
pxx-census: allocs=208613 frees=203428 live=5185 bytes=9552792 reuse=203414 list=0 bump=5199 arenas=1
pxx-census: sizes 32:61514 40:51835 48:60243 56:19458 64:4531 72:2610 88:6480 120:648 216:647 408:647
pxx-census: allocs=234690 frees=228855 live=5835 bytes=10746816 reuse=228844 list=0 bump=5846 arenas=1
pxx-census: sizes 32:69208 40:58315 48:67774 56:21886 64:5098 72:2934 88:7290 120:729 216:728 408:728
pxx-census: allocs=264027 frees=257466 live=6561 bytes=12090112 reuse=257451 list=0 bump=6576 arenas=1
pxx-census: sizes 32:77862 40:65603 48:76247 56:24621 64:5736 72:3299 88:8201 120:820 216:819 408:819
pxx-census: allocs=297031 frees=289648 live=7383 bytes=13601480 reuse=289634 list=0 bump=7397 arenas=1
pxx-census: sizes 32:87607 40:73802 48:85773 56:27694 64:6454 72:3708 88:9226 120:923 216:922 408:922
assert_no_leak[record_promo_member]: LEAK — live=7383 exceeds 50
  allocs=297031 frees=289648
  pxx-census: allocs=297031 frees=289648 live=7383 bytes=13601480 reuse=289634 list=0 bump=7397 arenas=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-18 — auto-closed by the borg watcher: `test-core#src:test/test_record_promo_member_leaks.pas` passes at 2b8480963d5f (tier native); it was red at 4fbed6c4157e. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
