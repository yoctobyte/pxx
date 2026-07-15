---
prio: 70
---

# regression: test-c-conformance-riscv32#shard0/6 red at ba5b85d6122d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-15T07:23:10Z
- **Test source:** tools/run_c_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-c-conformance-riscv32#shard0/6'` at ba5b85d6122d674c1b76890b52135618f70ea630

## Range
bad `ba5b85d6122d`, last good `ba5b85d6122d`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL 00187.c — output mismatch:
    --- library_candidates/c-testsuite/tests/single-exec/00187.c.expected	2026-07-07 21:11:07.000000000 +0200
    +++ /tmp/pxx_c_conformance.713527/out.txt	2026-07-15 09:20:06.728716445 +0200
    @@ -11,17 +11,3 @@
     ch: 108 'l'
     ch: 111 'o'
     ch: 10 '.'
    -ch: 104 'h'
    -ch: 101 'e'
test-c-conformance-riscv32: 36 pass, 1 fail, 0 skip (of 37)
test-c-conformance-riscv32: FAILURES: 00187.c(output)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
