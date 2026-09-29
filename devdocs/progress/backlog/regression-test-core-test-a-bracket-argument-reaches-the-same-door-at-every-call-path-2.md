---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 15 is `tools/expect_same.sh test_bracketdoor26 "$(/tmp/test_bracketdoor26 | tail -n 2)" "$(printf 'fails=0\nBRACKETDOOR OK')"`. The job's own `src` (`test/test_a_bracket_argument_reaches_the_same_door_at_every_call_path.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_a_bracket_argument_reaches_the_same_door_at_every_call_path`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_a_bracket_argument_reaches_the_same_door_at_every_call_path.pas at a69c18a0208e in step 2/15, `tools/expect_same.sh test_bracketdoor26 "$(/tmp/test_bracketdoor26 | tail -n 2)" "$(printf 'fails=0\nBRACKETDOOR OK')"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-29T03:10:02Z
- **Test source:** test/test_a_bracket_argument_reaches_the_same_door_at_every_call_path.pas tools/expect_same.sh
- **Failing step:** line 2 of 15 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_bracketdoor26 "$(/tmp/test_bracketdoor26 | tail -n 2)" "$(printf 'fails=0\nBRACKETDOOR OK')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_a_bracket_argument_reaches_the_same_door_at_every_call_path.pas'` at a69c18a0208eb10268a2642c7c6bd258880f104b

## Range
> **The named sha `a69c18a0208e` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `a69c18a0208e`, last good `fc6f76591258`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1768741/test_bracketdoor26  [code=87455B  data=38460B  bss=95772B  procs=957  codeseg=89824B]
expect_same: MISMATCH [test_bracketdoor26]
--- expected
+++ actual
@@ -1,2 +1,2 @@
-fails=0
-BRACKETDOOR OK
+FAIL array of Variant, instance method: got 33 want 66
+fails=2

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
