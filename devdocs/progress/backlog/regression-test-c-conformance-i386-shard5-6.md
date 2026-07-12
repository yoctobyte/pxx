---
prio: 70
---

# regression: test-c-conformance-i386#shard5/6 red at 96b6bac331d9 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-12T17:39:05Z
- **Test source:** tools/run_c_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-c-conformance-i386#shard5/6'` at 96b6bac331d9d8b9c838d0055a8e3841157314f1

## Range
bad `96b6bac331d9`, last good `96b6bac331d9`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL 00204.c — output mismatch:
    --- library_candidates/c-testsuite/tests/single-exec/00204.c.expected	2026-07-07 21:11:07.000000000 +0200
    +++ /tmp/pxx_c_conformance.209793/out.txt	2026-07-12 19:36:42.038689774 +0200
    @@ -102,58 +102,58 @@
     0
     abcd
     abcd0000
    -abcd00000000
    -abcd000000000000
test-c-conformance-i386: 35 pass, 1 fail, 0 skip (of 36)
test-c-conformance-i386: FAILURES: 00204.c(output)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
