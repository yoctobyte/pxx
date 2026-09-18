---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 3 of 3 is `tools/assert_no_leak.sh record_variant_member 50 /tmp/test_rvm26`. The job's own `src` (`test/test_record_variant_member_leaks.pas`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_record_variant_member_leaks`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `assert_no_leak`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_record_variant_member_leaks.pas at 4fbed6c4157e in step 3/3, `tools/assert_no_leak.sh record_variant_member 50 /tmp/test_rvm26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-18T10:37:47Z
- **Test source:** test/test_record_variant_member_leaks.pas tools/expect_same.sh +1
- **Failing step:** line 3 of 3 of the job's recipe; it names `tools/assert_no_leak.sh`.
  ```
  tools/assert_no_leak.sh record_variant_member 50 /tmp/test_rvm26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_record_variant_member_leaks.pas'` at 4fbed6c4157ef53972bae9ffb923ecf029f50725

## Range
> **The named sha `4fbed6c4157e` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `4fbed6c4157e`, last good `7f86a12a6628`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
list=0 bump=5873 arenas=1
pxx-census: sizes 64:4890 72:980 120:245 216:490 408:245
pxx-census: allocs=7707 frees=1100 live=6607 bytes=695728 reuse=1098 list=0 bump=6609 arenas=1
pxx-census: sizes 64:5503 72:1103 120:276 216:550 408:275
pxx-census: allocs=8671 frees=1239 live=7432 bytes=783104 reuse=1237 list=0 bump=7434 arenas=1
pxx-census: sizes 64:6191 72:1240 120:310 216:620 408:310
pxx-census: allocs=9755 frees=1393 live=8362 bytes=881032 reuse=1392 list=0 bump=8363 arenas=1
pxx-census: sizes 64:6964 72:1396 120:349 216:697 408:349
pxx-census: allocs=10975 frees=1567 live=9408 bytes=990912 reuse=1565 list=0 bump=9410 arenas=1
pxx-census: sizes 64:7839 72:1568 120:392 216:784 408:392
pxx-census: allocs=12347 frees=1763 live=10584 bytes=1114784 reuse=1761 list=0 bump=10586 arenas=1
pxx-census: sizes 64:8819 72:1764 120:441 216:882 408:441
pxx-census: allocs=13891 frees=1984 live=11907 bytes=1254144 reuse=1982 list=0 bump=11909 arenas=1
pxx-census: sizes 64:9921 72:1985 120:497 216:992 408:496
pxx-census: allocs=15628 frees=2232 live=13396 bytes=1410952 reuse=2230 list=0 bump=13398 arenas=1
pxx-census: sizes 64:11161 72:2234 120:559 216:1116 408:558
pxx-census: allocs=17582 frees=2511 live=15071 bytes=1587456 reuse=2509 list=0 bump=15073 arenas=1
pxx-census: sizes 64:12558 72:2512 120:628 216:1256 408:628
pxx-census: allocs=19780 frees=2827 live=16953 bytes=1786272 reuse=2825 list=0 bump=16955 arenas=1
pxx-census: sizes 64:14124 72:2828 120:707 216:1414 408:707
pxx-census: allocs=22253 frees=3179 live=19074 bytes=2009312 reuse=3177 list=0 bump=19076 arenas=1
pxx-census: sizes 64:15893 72:3180 120:795 216:1590 408:795
pxx-census: allocs=25035 frees=3576 live=21459 bytes=2260288 reuse=3574 list=0 bump=21461 arenas=1
pxx-census: sizes 64:17881 72:3577 120:895 216:1788 408:894
assert_no_leak[record_variant_member]: LEAK — live=21459 exceeds 50
  allocs=25035 frees=3576
  pxx-census: allocs=25035 frees=3576 live=21459 bytes=2260288 reuse=3574 list=0 bump=21461 arenas=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
