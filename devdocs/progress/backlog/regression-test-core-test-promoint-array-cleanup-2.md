---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 21 of 41 is `tools/assert_no_leak.sh managed_member_array 50 /tmp/test_mma26`. The job's own `src` (`test/test_promoint_array_cleanup.pas`, 4 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_promoint_array_cleanup`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `assert_no_leak`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_promoint_array_cleanup.pas at 4fbed6c4157e in step 21/41, `tools/assert_no_leak.sh managed_member_array 50 /tmp/test_mma26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-18T10:37:47Z
- **Test source:** test/test_promoint_array_cleanup.pas tools/expect_same.sh +2
- **Failing step:** line 21 of 41 of the job's recipe; it names `tools/assert_no_leak.sh`.
  ```
  tools/assert_no_leak.sh managed_member_array 50 /tmp/test_mma26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_promoint_array_cleanup.pas'` at 4fbed6c4157ef53972bae9ffb923ecf029f50725

## Range
> **The named sha `4fbed6c4157e` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `4fbed6c4157e`, last good `7f86a12a6628`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
0 bump=4598 arenas=1
pxx-census: sizes 32:68661 40:61059 48:70204 56:22918 64:1525 72:20 80:381 88:7634 240:764 456:762
pxx-census: allocs=264027 frees=258871 live=5156 bytes=12714744 reuse=257997 list=856 bump=5174 arenas=1
pxx-census: sizes 32:77248 40:68691 48:78981 56:25780 64:1716 72:20 80:429 88:8588 240:858 456:858
pxx-census: allocs=297031 frees=291228 live=5803 bytes=14302552 reuse=290251 list=962 bump=5818 arenas=1
pxx-census: sizes 32:86902 40:77283 48:88859 56:29001 64:1929 72:20 80:482 88:9661 240:966 456:964
pxx-census: allocs=334160 frees=327636 live=6524 bytes=16091944 reuse=326534 list=1084 bump=6542 arenas=1
pxx-census: sizes 32:97773 40:86939 48:99965 56:32622 64:2172 72:20 80:543 88:10868 240:1086 456:1086
pxx-census: allocs=375931 frees=368592 live=7339 bytes=18103688 reuse=367353 list=1220 bump=7358 arenas=1
pxx-census: sizes 32:110003 40:97803 48:112460 56:36697 64:2444 72:20 80:611 88:12227 240:1222 456:1222
pxx-census: allocs=422923 frees=414666 live=8257 bytes=20365800 reuse=413280 list=1372 bump=8271 arenas=1
pxx-census: sizes 32:123754 40:110035 48:126518 56:41281 64:2749 72:20 80:687 88:13755 240:1376 456:1374
pxx-census: allocs=475789 frees=466501 live=9288 bytes=22911752 reuse=464943 list=1544 bump=9302 arenas=1
pxx-census: sizes 32:139226 40:123787 48:142338 56:46438 64:3093 72:20 80:773 88:15474 240:1548 456:1546
pxx-census: allocs=535263 frees=524815 live=10448 bytes=25776264 reuse=523059 list=1738 bump=10466 arenas=1
pxx-census: sizes 32:156633 40:139259 48:160133 56:52240 64:3480 72:20 80:870 88:17408 240:1740 456:1740
pxx-census: allocs=602171 frees=590415 live=11756 bytes=28998856 reuse=588443 list=1956 bump=11772 arenas=1
pxx-census: sizes 32:176216 40:156667 48:180149 56:58768 64:3915 72:20 80:978 88:19584 240:1958 456:1958
assert_no_leak[managed_member_array]: LEAK — live=11756 exceeds 50
  allocs=602171 frees=590415
  pxx-census: allocs=602171 frees=590415 live=11756 bytes=28998856 reuse=588443 list=1956 bump=11772 arenas=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
