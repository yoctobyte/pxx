---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 13 is `tools/expect_same.sh test_tls_base26 "$(/tmp/test_tls_base26)" "$(printf 'errors=0\nTLS OK')"`. The job's own `src` (`test/test_tls_base.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_tls_base`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_tls_base.pas at bd35a383c7c2 in step 2/13, `tools/expect_same.sh test_tls_base26 "$(/tmp/test_tls_base26)" "$(printf 'errors=0\nTLS OK')"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-15T07:35:39Z
- **Test source:** test/test_tls_base.pas tools/expect_same.sh
- **Failing step:** line 2 of 13 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_tls_base26 "$(/tmp/test_tls_base26)" "$(printf 'errors=0\nTLS OK')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_tls_base.pas'` at bd35a383c7c2f9b7806de3b0af37bbd4e86f7a55

## Range
bad `bd35a383c7c2`, last good `03975f44d5d4`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3945206/test_tls_base26  [code=175896B  data=7592B  bss=58076B  procs=618]
expect_same: MISMATCH [test_tls_base26]
--- expected
+++ actual
@@ -1,2 +1 @@
-errors=0
-TLS OK
+errors=2

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
