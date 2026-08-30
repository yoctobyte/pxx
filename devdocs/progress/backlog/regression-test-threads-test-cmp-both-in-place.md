---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_cmp_both_in_place.pas@2 red at 0aa01425dbdc (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T02:36:29Z
- **Test source:** test/test_cmp_both_in_place.pas tools/expect_same.sh +1

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_cmp_both_in_place.pas@2'` at 0aa01425dbdc0fe8f676f40a314848ddefd78426

## Range
> **The named sha `0aa01425dbdc` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0aa01425dbdc`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
ok: /tmp/testmgr-scratch-3881983/test_cbip026  [code=83375B  data=2008B  bss=42460B  procs=131]
expect_same: MISMATCH [aarch64/test_cbip_a64_0]
--- expected
+++ actual
@@ -1 +1 @@
-3896084(printf 'acc=49149\none=16383\ndone')
+3896084(tools/run_target.sh aarch64 /tmp/testmgr-scratch-3881983/test_cbip_a64_0)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
