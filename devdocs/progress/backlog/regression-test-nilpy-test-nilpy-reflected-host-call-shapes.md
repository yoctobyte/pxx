---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 6 of 10 is `tools/expect_same.sh hostshape26/native "$(/tmp/test_nilpy_hostshape26 2>/dev/null)" "$(printf 'HOSTSHAPE-MODE wide\nHOS`. The job's own `src` (`test/test_nilpy_reflected_host_call_shapes.npy`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_nilpy_reflected_host_call_shapes`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# first-ever red: test-nilpy#src:test/test_nilpy_reflected_host_call_shapes.npy at 1086f130add0 in step 6/10, `tools/expect_same.sh hostshape26/native "$(/tmp/test_nilpy_hostshape26 2>/dev/null)" "$(printf 'HOSTSHAPE-MODE wide\nHO…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-29T04:13:47Z
- **Test source:** test/test_nilpy_reflected_host_call_shapes.npy tools/expect_same.sh +1
- **Failing step:** line 6 of 10 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh hostshape26/native "$(/tmp/test_nilpy_hostshape26 2>/dev/null)" "$(printf 'HOSTSHAPE-MODE wide\nHOSTSHAPE-CHECK failures=0')"
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_reflected_host_call_shapes.npy'` at 1086f130add067f3bb2730a5d4ba3fb1bb1e434a

## Range
> **The named sha `1086f130add0` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `1086f130add0`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-2046944/test_nilpy_hostshape26  [code=896006B  data=109172B  bss=70100B  procs=2309  codeseg=896736B]
Segmentation fault (core dumped)
expect_same: MISMATCH [hostshape26/native]
--- expected
+++ actual
@@ -1,2 +1 @@
-HOSTSHAPE-MODE wide
-HOSTSHAPE-CHECK failures=0
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
