---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 2 of 2, `ok=0; \ for t in native i386 arm32 aarch64 riscv32 xtensa wasm32; do \ case $t in \ native) bin=/tmp/fxpal26; run="";; \`, which names `test/test_cross_futex_through_the_pal.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# first-ever red: test-core#src:test/test_cross_futex_through_the_pal.pas at 0f13a3b760a3 in step 2/2, `ok=0; \ for t in native i386 arm32 aarch64 riscv32 xtensa wasm32; do \ case $t in \ native) bin=/tmp/fxpal26; run="";; …` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-04T13:51:08Z
- **Test source:** test/test_cross_futex_through_the_pal.pas tools/run_target.sh +1
- **Failing step:** line 2 of 2 of the job's recipe; it names `test/test_cross_futex_through_the_pal.pas tools/run_target.sh tools/expect_same.sh`.
  ```
  ok=0; \ for t in native i386 arm32 aarch64 riscv32 xtensa wasm32; do \ case $t in \ native) bin=/tmp/fxpal26; run="";; \ wasm32) ./compiler/pascal26 --target=wasm32 test/test_cross_futex_through_the_pal.pas /tmp/fxpal.wasm >/dev/null || { echo "fxpal wasm32 compile FAIL"; exit 1; }; \ bin=/tmp/fxpal
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_cross_futex_through_the_pal.pas'` at 0f13a3b760a337b82961e10c25986938125b76fb

## Range
> **The named sha `0f13a3b760a3` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0f13a3b760a3`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
  fxpal: PASS native (2^32+1 s did not return -- tv_sec is 64-bit)
  fxpal: PASS i386 (2^32+1 s truncated to 1 -- correct, its futex tv_sec IS 32-bit)
  fxpal: PASS arm32 (2^32+1 s truncated to 1 -- correct, its futex tv_sec IS 32-bit)
  fxpal: PASS aarch64 (2^32+1 s did not return -- tv_sec is 64-bit)
  fxpal: PASS riscv32 (2^32+1 s did not return -- tv_sec is 64-bit)
  fxpal: PASS xtensa (2^32+1 s truncated to 1 -- correct, its futex tv_sec IS 32-bit)
wasmtime not found (looked on PATH and in ~/.local/bin)
expect_same: MISMATCH [fxpal/wasm32-basic]
--- expected
+++ actual
@@ -1 +1 @@
-wake=-38 wait=-38 waitto=-38
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
