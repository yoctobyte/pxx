---
prio: 70
track: A
summary: "CLOSED 2026-09-24: not reproducible. At 8e68f024e2 (binary b51d542b4e1f) the aarch64 rows pass: the aarch64 and x86-64 outputs are identical, and assert_no_leak gives live=14 (bound 50) on both. Same stale filing as its test-core twin, closed the same day."
status: done
---

> **Track A from the job NAME `test-aarch64`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/test_dynarray_to_pointer_seam_leaks.pas`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **The SLUG names `test_dynarray_to_pointer_seam_leaks`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `assert_no_leak`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-aarch64#src:test/test_dynarray_to_pointer_seam_leaks.pas at 4fbed6c4157e in step 5/13, `tools/assert_no_leak.sh x86-64/dynarray_to_pointer_seam 50 /tmp/dtps_aarch64_x64` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-18T10:54:49Z
- **Test source:** test/test_dynarray_to_pointer_seam_leaks.pas tools/expect_same.sh +2
- **Failing step:** line 5 of 13 of the job's recipe; it names `tools/assert_no_leak.sh`.
  ```
  tools/assert_no_leak.sh x86-64/dynarray_to_pointer_seam 50 /tmp/dtps_aarch64_x64
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-aarch64#src:test/test_dynarray_to_pointer_seam_leaks.pas'` at 4fbed6c4157ef53972bae9ffb923ecf029f50725

## Range
> **The named sha `4fbed6c4157e` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `4fbed6c4157e`, last good `7f86a12a6628`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ve=5 bytes=94752 reuse=2364 list=0 bump=5 arenas=1
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
assert_no_leak[aarch64/dynarray_to_pointer_seam]: ok (allocs=10975 frees=10961 live=14, bound 50)
assert_no_leak[x86-64/dynarray_to_pointer_seam]: LEAK — live=999 exceeds 50
  allocs=10975 frees=9976
  pxx-census: allocs=10975 frees=9976 live=999 bytes=422888 reuse=9975 list=0 bump=1000 arenas=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-18 — the borg watcher saw `test-aarch64#src:test/test_dynarray_to_pointer_seam_leaks.pas` GREEN at 2b8480963d5f (tier full) and did NOT close this: the job's class is `qemu`, which testmgr treats as runtime-nondeterministic (RUN_RETRY_CLASSES) — a single pass does not refute a red there. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.

## Closed (2026-09-24, frankb-12)

Re-run at 8e68f024e2, binary b51d542b4e1f: the four Makefile rows (aarch64 and
x86-64 builds, expect_same, both assert_no_leak) all pass; live=14 against a
bound of 50 on both targets, identical census lines. Twin of
regression-test-core-test-dynarray-to-pointer-seam-leaks-2, closed together.
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit c0e0f5fe8c.
