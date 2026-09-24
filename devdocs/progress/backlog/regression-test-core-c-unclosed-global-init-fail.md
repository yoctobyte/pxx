---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 5 of 5 is `tools/expect_same.sh test_type_runtime26 "$(/tmp/test_type_runtime26)" "$(printf '1\n1\n1\n0\n1\n18446744065119617025\n1`. The job's own `src` (`test/c_unclosed_global_init_fail.c`, 5 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `c_unclosed_global_init_fail`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **This expectation records a REFUSAL** (a *_fail / {%FAIL} test). Before treating a converged bisect range as an accusation, check whether the named commit IMPLEMENTED the thing being refused -- a feature landing makes its own refusal test go red, and the bisect converges on it correctly. Not a verdict; the tool cannot decide this one.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/c_unclosed_global_init_fail.c at f61b926d210a in step 5/5, `tools/expect_same.sh test_type_runtime26 "$(/tmp/test_type_runtime26)" "$(printf '1\n1\n1\n0\n1\n18446744065119617025\n…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-24T23:08:39Z
- **Test source:** test/c_unclosed_global_init_fail.c test/c_unclosed_ptr_array_init_fail.c +3
- **Failing step:** line 5 of 5 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_type_runtime26 "$(/tmp/test_type_runtime26)" "$(printf '1\n1\n1\n0\n1\n18446744065119617025\n18446744073709551615\n9223372036854775807\n1\n-1\n-1\n-1\n18446744073709551615\n-1\n0\n2\n7\n123456\n9\n20')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/c_unclosed_global_init_fail.c'` at f61b926d210a7849ee0c40b6b97b3173f0b619f6

## Range
> **The named sha `f61b926d210a` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `f61b926d210a`, last good `44179a5d818b`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2575553/test_type_runtime26  [code=22912B  data=4872B  bss=35372B  procs=152  codeseg=24288B]
expect_same: MISMATCH [test_type_runtime26]
--- expected
+++ actual
@@ -17,4 +17,4 @@
 7
 123456
 9
-20
+8

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
