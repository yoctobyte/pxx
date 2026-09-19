---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_platform_defines_esp26 "$(/tmp/test_platform_defines_esp26)" "$(printf 'platform=esp\nend')"`. The job's own `src` (`test/test_platform_defines.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_platform_defines`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_platform_defines.pas@2 at d250db9d3678 in step 2/2, `tools/expect_same.sh test_platform_defines_esp26 "$(/tmp/test_platform_defines_esp26)" "$(printf 'platform=esp\nend')"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-19T19:12:52Z
- **Test source:** test/test_platform_defines.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_platform_defines_esp26 "$(/tmp/test_platform_defines_esp26)" "$(printf 'platform=esp\nend')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_platform_defines.pas@2'` at d250db9d36786f9f054b54f9428a507beca815b3

## Range
> **The named sha `d250db9d3678` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `d250db9d3678`, last good `27dd469f12c0`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
/tmp/testmgr-scratch-3604369/test_platform_defines_esp26: symbol lookup error: /tmp/testmgr-scratch-3604369/test_platform_defines_esp26: undefined symbol: putchar
(tail)
pascal26:12: warning: write/writeln emits nothing in an ESP-IDF object. The IDF console is esp_rom_printf, which the IDF link resolves: declare it `external` and call it (docs/targets/esp32.md, "Mode 2: ESP-IDF component"; examples/esp32/hello-c3 is a buildable example that prints). Or build a hosted image with --platform=posix.
ok: /tmp/testmgr-scratch-3604369/test_platform_defines_esp26  [code=68426B  data=5084B  bss=2532B  procs=157  codeseg=69232B]
/tmp/testmgr-scratch-3604369/test_platform_defines_esp26: symbol lookup error: /tmp/testmgr-scratch-3604369/test_platform_defines_esp26: undefined symbol: putchar
expect_same: MISMATCH [test_platform_defines_esp26]
--- expected
+++ actual
@@ -1,2 +1 @@
-platform=esp
-end
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
