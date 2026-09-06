---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_interface_containers_ts26 "$(/tmp/test_interface_containers_ts26)" "$(printf 'strarr: ok\nstat`. The job's own `src` (`test/test_interface_containers.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_interface_containers.pas@2 at 918842a5fd43 in step 2/2, `tools/expect_same.sh test_interface_containers_ts26 "$(/tmp/test_interface_containers_ts26)" "$(printf 'strarr: ok\nsta…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T12:52:28Z
- **Test source:** test/test_interface_containers.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_interface_containers_ts26 "$(/tmp/test_interface_containers_ts26)" "$(printf 'strarr: ok\nstatic: 3\ndyn: 0\nafter shrink: 0\nshrink: 0\nafter whole-copy nil-a: 0\nb still alive: pq\ncopy: 2\nrstatic: 0\nrdyn: 0\nrec after shrink: 0\nrshrink: 0\nrec after copy nil-a: 0\nrec
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_interface_containers.pas@2'` at 918842a5fd4324bf93b3d2eeb84f7840a5844d22

## Range
> **The named sha `918842a5fd43` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `918842a5fd43`, last good `12af8ef60bfd`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1028111/test_interface_containers_ts26  [code=81688B  data=5344B  bss=43564B  procs=149]
expect_same: MISMATCH [test_interface_containers_ts26]
--- expected
+++ actual
@@ -1,8 +1,8 @@
 strarr:  ok
 static:  3
-dyn:     0
-after shrink: 0
-shrink:  0
+dyn:     2
+after shrink: 2
+shrink:  4
 after whole-copy nil-a: 0
 b still alive: pq
 copy:    2

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
