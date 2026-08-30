---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_val_radix_and_optional_code.pas red at 6d68643f9799 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T19:09:55Z
- **Test source:** test/test_val_radix_and_optional_code.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_val_radix_and_optional_code.pas'` at 6d68643f9799d4e0311e91bcbb139625c3e437a3

## Range
> **The named sha `6d68643f9799` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `6d68643f9799`, last good `1d8db8667267`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1521107/test_val_radix26  [code=110360B  data=6448B  bss=42716B  procs=243]
expect_same: MISMATCH [test_val_radix26]
--- expected
+++ actual
@@ -1 +1 @@
-total ok 27 / 27
+total ok 23 / 23

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
