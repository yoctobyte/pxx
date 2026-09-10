---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 9 of 12, `out=$(./compiler/pascal26 -Itest/ffi_headers/ test/test_nilpy_a_referenced_symbol_from_a_library_that_cannot_exist.npy /`, which names `test/test_nilpy_a_referenced_symbol_from_a_library_that_cannot_exist.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/ffi_local/beside_the_source_wins.npy at a33eb37b4b16 in step 9/12, `out=$(./compiler/pascal26 -Itest/ffi_headers/ test/test_nilpy_a_referenced_symbol_from_a_library_that_cannot_exist.npy …` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `883da23adb0a`).
  Untriaged.
- **Found:** 2026-09-10T15:48:36Z
- **Test source:** test/ffi_local/beside_the_source_wins.npy test/ffi_local/beside_the_source_wins.expected +1
- **Failing step:** line 9 of 12 of the job's recipe; it names `test/test_nilpy_a_referenced_symbol_from_a_library_that_cannot_exist.npy`.
  ```
  out=$(./compiler/pascal26 -Itest/ffi_headers/ test/test_nilpy_a_referenced_symbol_from_a_library_that_cannot_exist.npy /tmp/test_nilpy_ffinolib26 2>&1); \ rc=$?; \ test "$rc" = "1" \ && printf '%s\n' "$out" | grep -q '^pascal26:10: error: this build would die at exec: `nolib_add` is imported from li
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/ffi_local/beside_the_source_wins.npy'` at a33eb37b4b1636f2a6a57b16b443a421a23ea780

## Range
> **The named sha `a33eb37b4b16` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `a33eb37b4b16`, last good `fe0905649dd6`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:1: error: this build would die at exec: `nolib_add` is imported from libnolib.so, which no library on this machine answers to. That soname was not declared anywhere — the compiler derived it from the name of the header you imported (nolib.h), and a header file name is not a library name. Name the library explicitly instead, with an `external '<soname>'` clause carrying the soname the loader wants.
(tail)
ok: /tmp/testmgr-scratch-2467831/test_nilpy_ffiloc26  [code=1281816B  data=82700B  bss=54864B  procs=2134]
test_nilpy_a_referenced_symbol_from_a_library_that_cannot_exist: FAIL - rc=1 (want 1, the exec diagnostic on line 10, no binary)
pascal26:1: error: this build would die at exec: `nolib_add` is imported from libnolib.so, which no library on this machine answers to. That soname was not declared anywhere — the compiler derived it from the name of the header you imported (nolib.h), and a header file name is not a library name. Name the library explicitly instead, with an `external '<soname>'` clause carrying the soname the loader wants.

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
