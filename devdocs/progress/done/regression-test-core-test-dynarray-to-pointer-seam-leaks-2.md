---
prio: 70
track: T
summary: "CLOSED 2026-09-24: not reproducible. The row `assert_no_leak.sh dynarray_to_pointer_seam 50` passes at 8e68f024e2 (binary b51d542b4e1f, x86-64): allocs=10975 frees=10961 live=14. It was not red in T's full run at pin v423, and the filed log tail itself shows live=5, so the recorded failure was not a leak."
status: done
---

> **Track T by default: the FAILING STEP named no owner.** Line 3 of 10 is `tools/assert_no_leak.sh dynarray_to_pointer_seam 50 /tmp/test_dtp26`. The job's own `src` (`test/test_dynarray_to_pointer_seam_leaks.pas`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_dynarray_to_pointer_seam_leaks`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `assert_no_leak`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_dynarray_to_pointer_seam_leaks.pas at 4fbed6c4157e in step 3/10, `tools/assert_no_leak.sh dynarray_to_pointer_seam 50 /tmp/test_dtp26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-18T10:37:47Z
- **Test source:** test/test_dynarray_to_pointer_seam_leaks.pas tools/expect_same.sh +1
- **Failing step:** line 3 of 10 of the job's recipe; it names `tools/assert_no_leak.sh`.
  ```
  tools/assert_no_leak.sh dynarray_to_pointer_seam 50 /tmp/test_dtp26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_dynarray_to_pointer_seam_leaks.pas'` at 4fbed6c4157ef53972bae9ffb923ecf029f50725

## Range
> **The named sha `4fbed6c4157e` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `4fbed6c4157e`, last good `7f86a12a6628`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
92 reuse=2100 list=0 bump=5 arenas=1
pxx-census: sizes 32:1 40:2104
pxx-census: allocs=2369 frees=2364 live=5 bytes=94752 reuse=2364 list=0 bump=5 arenas=1
pxx-census: sizes 32:1 40:2368
pxx-census: allocs=2666 frees=2661 live=5 bytes=106632 reuse=2661 list=0 bump=5 arenas=1
pxx-census: sizes 32:1 40:2665
pxx-census: allocs=3000 frees=2995 live=5 bytes=119992 reuse=2995 list=0 bump=5 arenas=1
pxx-census: sizes 32:1 40:2999
pxx-census: allocs=3376 frees=3370 live=6 bytes=135032 reuse=3370 list=0 bump=6 arenas=1
pxx-census: sizes 32:1 40:3375
pxx-census: allocs=3799 frees=3793 live=6 bytes=151952 reuse=3793 list=0 bump=6 arenas=1
pxx-census: sizes 32:1 40:3798
pxx-census: allocs=4274 frees=4263 live=11 bytes=169496 reuse=4263 list=0 bump=11 arenas=1
pxx-census: sizes 32:183 40:4091
pxx-census: allocs=4809 frees=4800 live=9 bytes=188048 reuse=4798 list=0 bump=11 arenas=1
pxx-census: sizes 32:539 40:4270
pxx-census: allocs=5411 frees=5400 live=11 bytes=208912 reuse=5400 list=0 bump=11 arenas=1
pxx-census: sizes 32:941 40:4470
pxx-census: allocs=6088 frees=6078 live=10 bytes=232384 reuse=6077 list=0 bump=11 arenas=1
pxx-census: sizes 32:1392 40:4696
pxx-census: allocs=6850 frees=6840 live=10 bytes=258800 reuse=6839 list=0 bump=11 arenas=1
pxx-census: sizes 32:1900 40:4950
pxx-census: allocs=7707 frees=7695 live=12 bytes=289448 reuse=7695 list=0 bump=12 arenas=1
pxx-census: sizes 32:2354 40:5353
pxx-census: allocs=8671 frees=8659 live=12 bytes=324152 reuse=8659 list=0 bump=12 arenas=1
pxx-census: sizes 32:2836 40:5835
pxx-census: allocs=9755 frees=9366 live=389 bytes=369208 reuse=9365 list=0 bump=390 arenas=1
pxx-census: sizes 32:3378 40:6000 56:377
pxx-census: allocs=10975 frees=9976 live=999 bytes=422888 reuse=9975 list=0 bump=1000 arenas=1
pxx-census: sizes 32:3988 40:6000 56:987
assert_no_leak[dynarray_to_pointer_seam]: LEAK — live=999 exceeds 50
  allocs=10975 frees=9976
  pxx-census: allocs=10975 frees=9976 live=999 bytes=422888 reuse=9975 list=0 bump=1000 arenas=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Closed (2026-09-24, frankb-12)

Re-run at 8e68f024e2, binary b51d542b4e1f, x86-64, from the repo root:
`-dPXX_ALLOC_CENSUS test/test_dynarray_to_pointer_seam_leaks.pas`, then
`tools/assert_no_leak.sh dynarray_to_pointer_seam 50` -> ok, allocs=10975
frees=10961 live=14. Not red in T's full run at pin v423 (per the coordinator).
The log tail filed above already reads live=5, under the bound, so whatever
reddened step 3 on 09-18 was not the leak the slug names. A dynarray leak
census the same day (22 shapes, x86-64 and i386) found one unrelated leak, a
by-value dynarray parameter rebound in the callee; handed to franks-a3.
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit c0e0f5fe8c.
