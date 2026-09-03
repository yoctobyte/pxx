---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 12 of 4 is `tools/expect_same.sh test_strn_container26 "$(/tmp/test_strn_container26)" "$(printf 'openp1 1\nopenp2 1\nopenp20 1\nope`. The job's own `src` (`test/test_string_n_container_strides.pas`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_string_n_container_strides.pas at 71a66c7d1437 in step 12/4, `tools/expect_same.sh test_strn_container26 "$(/tmp/test_strn_container26)" "$(printf 'openp1 1\nopenp2 1\nopenp20 1\nop…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-03T10:47:27Z
- **Test source:** test/test_string_n_container_strides.pas test/test_shortstring_byte_prefix.pas +1
- **Failing step:** line 12 of 4 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_strn_container26 "$(/tmp/test_strn_container26)" "$(printf 'openp1 1\nopenp2 1\nopenp20 1\nopenvals 1\ndyn1d 1\ndyn2d 1\ndyn2dvals 1\nguard 1')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_string_n_container_strides.pas'` at 71a66c7d14374aa793b9a200f23c41626c1d2879

## Range
> **The named sha `71a66c7d1437` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `71a66c7d1437`, last good `5d083bd91f9a`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3917500/test_strn_container26  [code=73496B  data=3280B  bss=44296B  procs=138]
ok: /tmp/testmgr-scratch-3917500/test_ssbp_short26  [code=69400B  data=3304B  bss=43556B  procs=134]
expect_same: MISMATCH [test_strn_container26]
--- expected
+++ actual
@@ -4,5 +4,5 @@
 openvals   1
 dyn1d      1
 dyn2d      1
-dyn2dvals  1
+dyn2dvals  0
 guard      1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
