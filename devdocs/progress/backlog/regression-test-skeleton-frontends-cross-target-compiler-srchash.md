---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 43 of 43 is `overall=0; ran=0; \ for src in test/test_rust_else_if.rs test/test_rust_advanced.rs \ test/test_rust_option.rs test/test`. The job's own `src` (`tools/compiler_srchash.sh`, 16 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `compiler_srchash`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `test_rust_else_if`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-skeleton-frontends-cross-target#src:tools/compiler_srchash.sh at 80e96e1c23cf in step 43/43, `overall=0; ran=0; \ for src in test/test_rust_else_if.rs test/test_rust_advanced.rs \ test/test_rust_option.rs test/tes…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-27T21:39:41Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +14
- **Failing step:** line 43 of 43 of the job's recipe; it names `test/test_rust_else_if.rs test/test_rust_advanced.rs test/test_rust_option.rs test/test_rust_result.rs`.
  ```
  overall=0; ran=0; \ for src in test/test_rust_else_if.rs test/test_rust_advanced.rs \ test/test_rust_option.rs test/test_rust_result.rs \ test/test_zig_skeleton.zig test/test_zig_structs.zig \ test/test_erlang_skeleton.erl test/test_ada_skeleton.adb \ test/test_ws_skeleton.ws test/test_lolcode_skele
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-skeleton-frontends-cross-target#src:tools/compiler_srchash.sh'` at 80e96e1c23cf7782f2f6c4d587c581f9794cfb69

## Range
> **The named sha `80e96e1c23cf` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `80e96e1c23cf`, last good `98facdd35ac7`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
self-host fixedpoint: verified — 1 round(s), ef9fe9c4bef9 (stamp read back; sources match it)
expect_same: MISMATCH [xtarget-test_rust_option.rs-i386]
--- expected
+++ actual
@@ -21,4 +21,4 @@
 circle 6
 rect 15
 nothing
-rc=0
+rc=81
expect_same: MISMATCH [xtarget-test_rust_result.rs-i386]
--- expected
+++ actual
@@ -8,4 +8,4 @@
 pos err 3
 big 10 11 12 13
 big none
-rc=0
+rc=81
test-skeleton-frontends-cross-target: test_lolcode_skeleton.lol REFUSED for riscv32 by the frontend, on purpose
test-skeleton-frontends-cross-target: test_fortran_skeleton.f90 REFUSED for i386 by the frontend, on purpose
test-skeleton-frontends-cross-target: test_algol_skeleton.alg REFUSED for i386 by the frontend, on purpose
test-skeleton-frontends-cross-target: test_basic_comprehensive.bas:riscv32 is a KNOWN GAP -- bug-a-the-basic-frontend-cannot-build-for-riscv32-the-only-driver-with-no-unit-pull
test-skeleton-frontends-cross-target: RED

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
