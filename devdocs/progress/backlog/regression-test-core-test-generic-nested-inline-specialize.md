---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 7 is `tools/expect_same.sh test_generic_nested_spec26 "$(/tmp/test_generic_nested_spec26)" "$(printf 'var: 7\nfield: 4\nparam:`. The job's own `src` (`test/test_generic_nested_inline_specialize.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_generic_nested_inline_specialize.pas at ff7b4f2edb76 in step 2/7, `tools/expect_same.sh test_generic_nested_spec26 "$(/tmp/test_generic_nested_spec26)" "$(printf 'var: 7\nfield: 4\nparam…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `0c5ad13167ab`).
  Untriaged.
- **Found:** 2026-09-09T12:26:00Z
- **Test source:** test/test_generic_nested_inline_specialize.pas tools/expect_same.sh
- **Failing step:** line 2 of 7 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_generic_nested_spec26 "$(/tmp/test_generic_nested_spec26)" "$(printf 'var: 7\nfield: 4\nparam: 7\nresult:5\nlocal: 9\ncross: 3/three n=1')" \ || { echo "test_generic_nested_inline_specialize: FAIL"; /tmp/test_generic_nested_spec26; exit 1; }
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_generic_nested_inline_specialize.pas'` at ff7b4f2edb768905c648f2cdf8892ba0f45368aa

## Range
> **The named sha `ff7b4f2edb76` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `ff7b4f2edb76`, last good `7525966a57fc`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-568842/test_generic_nested_spec26  [code=327448B  data=33944B  bss=85140B  procs=854]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_generic_nested_spec26]
--- expected
+++ actual
@@ -3,4 +3,3 @@
 param: 7
 result:5
 local: 9
-cross: 3/three n=1
test_generic_nested_inline_specialize: FAIL
var:   7
field: 4
param: 7
result:5
local: 9
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
