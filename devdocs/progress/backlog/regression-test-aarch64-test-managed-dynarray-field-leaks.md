---
prio: 70
track: A
---

> **Track A from the job NAME `test-aarch64`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/test_managed_dynarray_field_leaks.pas`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-aarch64#src:test/test_managed_dynarray_field_leaks.pas at 0d3d061121a7 in step 4/5, `tools/assert_no_leak.sh aarch64/managed_dynarray_field 50 tools/run_target.sh aarch64 $(TESTTMP)/mdf_aarch64` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-09-01T15:42:50Z
- **Test source:** test/test_managed_dynarray_field_leaks.pas tools/expect_same.sh +2
- **Failing step:** line 4 of 5 of the job's recipe; it names `tools/assert_no_leak.sh tools/run_target.sh`.
  ```
  tools/assert_no_leak.sh aarch64/managed_dynarray_field 50 tools/run_target.sh aarch64 /tmp/mdf_aarch64
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-aarch64#src:test/test_managed_dynarray_field_leaks.pas'` at 0d3d061121a7d88f9e350499c6a4e395d710ec0a

## Range
> **The named sha `0d3d061121a7` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0d3d061121a7`, last good `3e6249872671`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
nas=1
pxx-census: sizes 32:4566 48:1522
pxx-census: allocs=6850 frees=6848 live=2 bytes=246608 reuse=6846 list=0 bump=4 arenas=1
pxx-census: sizes 32:5137 48:1713
pxx-census: allocs=7707 frees=7704 live=3 bytes=277456 reuse=7703 list=0 bump=4 arenas=1
pxx-census: sizes 32:5780 48:1927
pxx-census: allocs=8671 frees=8669 live=2 bytes=309472 reuse=8667 list=0 bump=4 arenas=1
pxx-census: sizes 32:6671 48:2000
pxx-census: allocs=9755 frees=9752 live=3 bytes=344160 reuse=9751 list=0 bump=4 arenas=1
pxx-census: sizes 32:7755 48:2000
pxx-census: allocs=10975 frees=10973 live=2 bytes=383200 reuse=10971 list=0 bump=4 arenas=1
pxx-census: sizes 32:8975 48:2000
pxx-census: allocs=12347 frees=12344 live=3 bytes=428904 reuse=12340 list=0 bump=7 arenas=1
pxx-census: sizes 32:10122 40:225 48:2000
pxx-census: allocs=13891 frees=13886 live=5 bytes=480368 reuse=13884 list=0 bump=7 arenas=1
pxx-census: sizes 32:11409 40:482 48:2000
pxx-census: allocs=15628 frees=15626 live=2 bytes=538272 reuse=15621 list=0 bump=7 arenas=1
pxx-census: sizes 32:12856 40:772 48:2000
pxx-census: allocs=17582 frees=17580 live=2 bytes=602624 reuse=17574 list=0 bump=8 arenas=1
pxx-census: sizes 16:117 32:14348 40:1000 48:2117
pxx-census: allocs=19780 frees=19775 live=5 bytes=672960 reuse=19772 list=0 bump=8 arenas=1
pxx-census: sizes 16:556 32:15668 40:1000 48:2556
pxx-census: allocs=22253 frees=22252 live=1 bytes=754136 reuse=22244 list=0 bump=9 arenas=1
pxx-census: sizes 16:1000 32:17168 40:1000 48:3000 56:85
pxx-census: allocs=25035 frees=25033 live=2 bytes=864848 reuse=25025 list=0 bump=10 arenas=1
pxx-census: sizes 16:1023 32:19000 40:1012 48:3000 56:1000
pxx-census: allocs=28165 frees=28054 live=111 bytes=942600 reuse=28050 list=0 bump=115 arenas=1
pxx-census: sizes 16:3000 32:19110 40:2000 48:3000 56:1055
assert_no_leak[aarch64/managed_dynarray_field]: LEAK — live=111 exceeds 50
  allocs=28165 frees=28054
  pxx-census: allocs=28165 frees=28054 live=111 bytes=942600 reuse=28050 list=0 bump=115 arenas=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## The bound in this heading was WRONG when filed — it read `5`, the real one is `50`

Corrected 2026-09-01. Not a typo and not a transcription slip: `twatch.py`
truncated the failing step to 56 characters and appended the closing backtick
afterwards, and this step is **exactly 56 characters up to the `5`**. The cut
fell between the two digits of the bound, so the heading read a complete,
well-formed command with a bound off by a factor of ten. Nothing looked
truncated — that is the whole problem with amputating a number.

Verified the bound was never 5: `git show 0d3d061121a7:Makefile` and its parent
both carry `50`, and exactly one commit (`2b70ff387`) has ever touched that line.

Fixed in `tools/twatch.py` — the cap is 120 and a truncation now ends in `…`.
